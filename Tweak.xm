#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// ==================== 常量定义 ====================
static NSString * const kIsTargetTaskKey = @"FakeResponse_IsTargetTask";
static NSString * const kFakeDataHandledKey = @"FakeResponse_Handled";
static NSString * const kDelegateWrappedKey = @"FakeResponse_DelegateWrapped";
static const NSInteger kSuccessStatusCode = 200;
static NSString * const kTargetPath = @"nwgt/web/api/v1/menu/validate";

// ==================== 工具函数 ====================

// 判断是否为目标请求
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    
    // 只拦截 HTTP/HTTPS
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    
    NSString *urlStr = [request.URL absoluteString];
    BOOL isTarget = [urlStr containsString:kTargetPath];
    
#if DEBUG
    if (isTarget) {
        NSLog(@"[Hook] 🎯 目标请求: %@", urlStr);
    }
#endif
    
    return isTarget;
}

// Gzip 压缩
static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    
    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    
    // 15+16 表示使用 gzip 格式
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15 + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    
    NSMutableData *compressed = [NSMutableData dataWithLength:16384];
    int ret;
    do {
        if (strm.total_out >= compressed.length) {
            [compressed increaseLengthBy:16384];
        }
        strm.next_out = ((Bytef *)compressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
        ret = deflate(&strm, Z_FINISH);
    } while (ret == Z_OK);
    
    deflateEnd(&strm);
    
    if (ret != Z_STREAM_END) {
        return nil;
    }
    
    [compressed setLength:strm.total_out];
    return compressed;
}

// 生成伪造数据（带缓存）
static NSData *getFakeJsonData() {
    static NSData *cachedFakeData = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        NSDictionary *obj = @{
            @"sing": [NSNull null],
            @"data": [NSNull null],
            @"code": @0,
            @"message": @"请求成功",
            @"success": @YES,
            @"skey": [NSNull null],
            @"timestamp": @(ts)
        };
        
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
        
        if (error) {
            NSLog(@"[Error] JSON 序列化失败: %@", error);
            return;
        }
        
        cachedFakeData = gzipData(jsonData);
        if (!cachedFakeData) {
            NSLog(@"[Error] Gzip 压缩失败");
        } else {
#if DEBUG
            NSLog(@"[Init] ✅ 伪造数据已生成，长度: %lu", (unsigned long)cachedFakeData.length);
#endif
        }
    });
    return cachedFakeData;
}

// ==================== URLProtocol 实现 ====================
@interface FakeResponseURLProtocol : NSURLProtocol
@end

@implementation FakeResponseURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 避免重复处理
    if ([NSURLProtocol propertyForKey:kFakeDataHandledKey inRequest:request]) {
        return NO;
    }
    
    // 只拦截目标请求
    return isTargetRequest(request);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void)startLoading {
    NSData *fakeData = getFakeJsonData();
    
    // 如果伪造数据生成失败，降级到真实请求
    if (!fakeData) {
#if DEBUG
        NSLog(@"[Protocol] ⚠️ 伪造数据失败，降级到真实请求");
#endif
        
        NSMutableURLRequest *newRequest = [self.request mutableCopy];
        [NSURLProtocol setProperty:@YES forKey:kFakeDataHandledKey inRequest:newRequest];
        
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:newRequest 
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    [self.client URLProtocol:self didFailWithError:error];
                } else {
                    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
                    [self.client URLProtocol:self didLoadData:data];
                    [self.client URLProtocolDidFinishLoading:self];
                }
            }];
        [task resume];
        return;
    }
    
#if DEBUG
    NSLog(@"[Protocol] 📡 返回伪造数据，长度: %lu", (unsigned long)fakeData.length);
#endif
    
    // 构造伪造的响应头
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] 
        initWithURL:self.request.URL 
        statusCode:kSuccessStatusCode 
        HTTPVersion:@"HTTP/1.1" 
        headerFields:@{
            @"Content-Type": @"application/json",
            @"Content-Encoding": @"gzip",
            @"Content-Length": @(fakeData.length).stringValue,
            @"Cache-Control": @"no-cache"
        }];
    
    // 发送响应头
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    
    // 发送数据
    [self.client URLProtocol:self didLoadData:fakeData];
    
    // 完成加载
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 无需额外操作
}

@end

// ==================== Delegate 包装器（备用方案）====================
@interface FakeDataDelegate : NSObject <NSURLSessionDataDelegate> {
    __unsafe_unretained id<NSURLSessionDataDelegate> _originalDelegate;
    BOOL _hasSentFakeData;
    dispatch_queue_t _syncQueue;
}
@property (nonatomic, assign) id<NSURLSessionDataDelegate> originalDelegate;
@property (atomic, assign) BOOL hasSentFakeData;
@end

@implementation FakeDataDelegate

@synthesize originalDelegate = _originalDelegate;
@synthesize hasSentFakeData = _hasSentFakeData;

- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _hasSentFakeData = NO;
        _syncQueue = dispatch_queue_create("com.fake.delegate.sync", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    // ARC 环境下不需要手动 release dispatch queue
    // 非 ARC 环境需要释放
#if !__has_feature(objc_arc)
    if (_syncQueue) {
        dispatch_release(_syncQueue);
    }
    [super dealloc];
#endif
}

- (void)URLSession:(NSURLSession *)session 
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    
    __block BOOL shouldFake = NO;
    dispatch_sync(_syncQueue, ^{
        shouldFake = !_hasSentFakeData && isTargetRequest(dataTask.originalRequest);
    });
    
    if (shouldFake) {
        NSData *fakeData = getFakeJsonData();
        if (!fakeData) {
#if DEBUG
            NSLog(@"[Delegate] ⚠️ 伪造数据失败，使用原始响应");
#endif
            if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
                [_originalDelegate URLSession:session
                                     dataTask:dataTask
                           didReceiveResponse:response
                            completionHandler:completionHandler];
            } else if (completionHandler) {
                completionHandler(NSURLSessionResponseAllow);
            }
            return;
        }
        
#if DEBUG
        NSLog(@"[Delegate] 🎯 拦截响应，返回伪造数据");
#endif
        
        // 构造伪造响应
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
            initWithURL:response.URL
            statusCode:kSuccessStatusCode
            HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Content-Type": @"application/json", 
                          @"Content-Encoding": @"gzip"}];
        
        // 转发伪造响应
        if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
            [_originalDelegate URLSession:session
                                 dataTask:dataTask
                       didReceiveResponse:fakeResponse
                        completionHandler:^(NSURLSessionResponseDisposition disposition) {
                if (completionHandler) {
                    completionHandler(NSURLSessionResponseAllow);
                }
            }];
        } else if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
        
#if !__has_feature(objc_arc)
        [fakeResponse release];
#endif
    } else {
        // 转发原始响应
        if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
            [_originalDelegate URLSession:session
                                 dataTask:dataTask
                       didReceiveResponse:response
                        completionHandler:completionHandler];
        } else if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    
    __block BOOL shouldFake = NO;
    __block BOOL alreadySent = NO;
    
    dispatch_sync(_syncQueue, ^{
        alreadySent = _hasSentFakeData;
        shouldFake = !alreadySent && isTargetRequest(dataTask.originalRequest);
        if (shouldFake) {
            _hasSentFakeData = YES;
        }
    });
    
    if (shouldFake) {
        NSData *fakeData = getFakeJsonData();
        if (fakeData) {
#if DEBUG
            NSLog(@"[Delegate] ✅ 注入伪造数据，长度: %lu", (unsigned long)fakeData.length);
#endif
            
            if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
                [_originalDelegate URLSession:session
                                     dataTask:dataTask
                               didReceiveData:fakeData];
            }
            return;
        }
    }
    
    // 转发原始数据
    if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [_originalDelegate URLSession:session
                             dataTask:dataTask
                       didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    
    __block BOOL shouldFake = NO;
    __block BOOL alreadySent = NO;
    
    dispatch_sync(_syncQueue, ^{
        alreadySent = _hasSentFakeData;
        shouldFake = !alreadySent && isTargetRequest(task.originalRequest);
        if (shouldFake) {
            _hasSentFakeData = YES;
        }
    });
    
    if (shouldFake) {
#if DEBUG
        NSLog(@"[Delegate] ⚠️ 未收到数据回调，在完成时注入");
#endif
        
        NSData *fakeData = getFakeJsonData();
        if (fakeData && [_originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [_originalDelegate URLSession:session
                                 dataTask:(NSURLSessionDataTask *)task
                           didReceiveData:fakeData];
        }
        
        // 完成时不传递错误，表示成功
        if ([_originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [_originalDelegate URLSession:session task:task didCompleteWithError:nil];
        }
    } else {
        // 转发原始完成
        if ([_originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [_originalDelegate URLSession:session task:task didCompleteWithError:error];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([_originalDelegate respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)]) {
        [_originalDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
    } else if (completionHandler) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *))completionHandler {
    if ([_originalDelegate respondsToSelector:@selector(URLSession:dataTask:willCacheResponse:completionHandler:)]) {
        [_originalDelegate URLSession:session
                             dataTask:dataTask
                    willCacheResponse:proposedResponse
                    completionHandler:completionHandler];
    } else if (completionHandler) {
        completionHandler(proposedResponse);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if ([_originalDelegate respondsToSelector:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)]) {
        [_originalDelegate URLSession:session
                                  task:task
            willPerformHTTPRedirection:response
                            newRequest:request
                     completionHandler:completionHandler];
    } else if (completionHandler) {
        completionHandler(request);
    }
}

@end

// ==================== Hook NSURLSession ====================
%hook NSURLSession

// Hook setDelegate 方法以包装 delegate
- (void)setDelegate:(id<NSURLSessionDelegate>)delegate {
    static NSMutableSet *wrappedSessions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wrappedSessions = [[NSMutableSet alloc] init];
    });
    
    @synchronized(wrappedSessions) {
        if (delegate && [delegate conformsToProtocol:@protocol(NSURLSessionDataDelegate)]) {
            NSValue *sessionKey = [NSValue valueWithNonretainedObject:self];
            if (![wrappedSessions containsObject:sessionKey]) {
                FakeDataDelegate *wrapper = [[FakeDataDelegate alloc] initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate];
                %orig(wrapper);
                [wrappedSessions addObject:sessionKey];
#if DEBUG
                NSLog(@"[Hook] ✅ 已包装 session delegate");
#endif
                return;
            }
        }
    }
    
    %orig;
}

// Hook dataTask 方法以标记目标任务
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig(request);
    
    if (isTargetRequest(request)) {
#if DEBUG
        NSLog(@"[Hook] 🎯 标记目标任务: %@", request.URL);
#endif
        objc_setAssociatedObject(task, (__bridge const void *)kIsTargetTaskKey, @YES, OBJC_ASSOCIATION_RETAIN);
    }
    
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    // 对于 completionHandler 模式，直接替换回调
    if (isTargetRequest(request) && completionHandler) {
#if DEBUG
        NSLog(@"[Hook] 🎯 拦截 completionHandler 模式请求");
#endif
        
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *fakeData = getFakeJsonData();
            if (fakeData) {
#if DEBUG
                NSLog(@"[Hook] ✅ 使用伪造数据替换原始回调");
#endif
                completionHandler(fakeData, response, nil);
            } else {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, newHandler);
    }
    
    return %orig(request, completionHandler);
}

%end

// ==================== 自动注册 ====================
__attribute__((constructor))
static void initializeFakeResponseProtocol() {
    NSLog(@"[Init] 🚀 初始化网络拦截器 v2.0");
    
    // 注册 URLProtocol
    [NSURLProtocol registerClass:[FakeResponseURLProtocol class]];
    
    NSLog(@"[Init] ✅ URLProtocol 注册完成");
}

// ==================== 可选：禁用特定请求的拦截 ====================
@interface NSURLRequest (FakeResponse)
@property (nonatomic, assign) BOOL shouldUseFakeResponse;
@end

@implementation NSURLRequest (FakeResponse)

- (BOOL)shouldUseFakeResponse {
    NSNumber *value = objc_getAssociatedObject(self, @selector(shouldUseFakeResponse));
    return value ? [value boolValue] : YES;
}

- (void)setShouldUseFakeResponse:(BOOL)shouldUseFakeResponse {
    objc_setAssociatedObject(self, @selector(shouldUseFakeResponse), @(shouldUseFakeResponse), OBJC_ASSOCIATION_RETAIN);
}

@end