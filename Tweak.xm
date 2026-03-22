#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// ==================== 常量定义 ====================
static NSString * const kIsTargetTaskKey = @"FakeResponse_IsTargetTask";
static NSString * const kFakeDataHandledKey = @"FakeResponse_Handled";
static NSString * const kOriginalDelegateKey = @"FakeResponse_OriginalDelegate";
static const NSInteger kSuccessStatusCode = 200;
static NSString * const kTargetPath = @"nwgt/web/api/v1/menu/validate";

// ==================== 工具函数 ====================

static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    
    NSString *urlStr = [request.URL absoluteString];
    return [urlStr containsString:kTargetPath];
}

static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    
    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    
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
            NSLog(@"[Error] JSON serialization failed: %@", error);
            return;
        }
        
        cachedFakeData = gzipData(jsonData);
    });
    return cachedFakeData;
}

// ==================== URLProtocol 实现 ====================
@interface FakeResponseURLProtocol : NSURLProtocol
@end

@implementation FakeResponseURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kFakeDataHandledKey inRequest:request]) {
        return NO;
    }
    return isTargetRequest(request);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSData *fakeData = getFakeJsonData();
    
    if (!fakeData) {
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
    
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] 
        initWithURL:self.request.URL 
        statusCode:kSuccessStatusCode 
        HTTPVersion:@"HTTP/1.1" 
        headerFields:@{
            @"Content-Type": @"application/json",
            @"Content-Encoding": @"gzip"
        }];
    
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [self.client URLProtocol:self didLoadData:fakeData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 无需操作
}

@end

// ==================== Delegate 包装器 ====================
@interface AlamofireDelegateWrapper : NSObject <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, weak) id originalDelegate;
@property (nonatomic, assign) BOOL hasSentFakeData;
@end

@implementation AlamofireDelegateWrapper

- (instancetype)initWithDelegate:(id)delegate {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _hasSentFakeData = NO;
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session 
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    
    if (!self.hasSentFakeData && isTargetRequest(dataTask.originalRequest)) {
        NSData *fakeData = getFakeJsonData();
        if (fakeData) {
            self.hasSentFakeData = YES;
            
            NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
                initWithURL:response.URL
                statusCode:kSuccessStatusCode
                HTTPVersion:@"HTTP/1.1"
                headerFields:@{
                    @"Content-Type": @"application/json",
                    @"Content-Encoding": @"gzip"
                }];
            
            if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
                [self.originalDelegate URLSession:session
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
            return;
        }
    }
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        [self.originalDelegate URLSession:session
                                 dataTask:dataTask
                       didReceiveResponse:response
                        completionHandler:completionHandler];
    } else if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    
    if (!self.hasSentFakeData && isTargetRequest(dataTask.originalRequest)) {
        self.hasSentFakeData = YES;
        
        NSData *fakeData = getFakeJsonData();
        if (fakeData) {
            if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
                [self.originalDelegate URLSession:session
                                         dataTask:dataTask
                                   didReceiveData:fakeData];
            }
            return;
        }
    }
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [self.originalDelegate URLSession:session
                                 dataTask:dataTask
                           didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    
    if (!self.hasSentFakeData && isTargetRequest(task.originalRequest)) {
        self.hasSentFakeData = YES;
        
        NSData *fakeData = getFakeJsonData();
        if (fakeData && [self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [self.originalDelegate URLSession:session
                                     dataTask:(NSURLSessionDataTask *)task
                               didReceiveData:fakeData];
        }
        
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:nil];
        }
    } else {
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didReceiveChallenge:completionHandler:)]) {
        [self.originalDelegate URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
    } else if (completionHandler) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end

// ==================== Hook NSURLSession ====================
%hook NSURLSession

- (void)setDelegate:(id<NSURLSessionDelegate>)delegate {
    static NSMutableSet *wrappedSessions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wrappedSessions = [[NSMutableSet alloc] init];
    });
    
    @synchronized(wrappedSessions) {
        NSValue *sessionKey = [NSValue valueWithNonretainedObject:self];
        
        if (![wrappedSessions containsObject:sessionKey]) {
            if (delegate && [delegate conformsToProtocol:@protocol(NSURLSessionDataDelegate)]) {
                AlamofireDelegateWrapper *wrapper = [[AlamofireDelegateWrapper alloc] initWithDelegate:delegate];
                objc_setAssociatedObject(self, (__bridge const void *)kOriginalDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
                %orig(wrapper);
                [wrappedSessions addObject:sessionKey];
                return;
            }
        }
    }
    
    %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig(request);
    
    if (isTargetRequest(request)) {
        objc_setAssociatedObject(task, (__bridge const void *)kIsTargetTaskKey, @YES, OBJC_ASSOCIATION_RETAIN);
    }
    
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isTargetRequest(request) && completionHandler) {
        return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *fakeData = getFakeJsonData();
            if (fakeData) {
                completionHandler(fakeData, response, nil);
            } else {
                completionHandler(data, response, error);
            }
        });
    }
    
    return %orig(request, completionHandler);
}

%end

// ==================== Hook NSURLSessionConfiguration ====================
%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    
    NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
    BOOL hasProtocol = NO;
    for (Class cls in protocols) {
        if (cls == [FakeResponseURLProtocol class]) {
            hasProtocol = YES;
            break;
        }
    }
    
    if (!hasProtocol) {
        [protocols insertObject:[FakeResponseURLProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    
    NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses];
    BOOL hasProtocol = NO;
    for (Class cls in protocols) {
        if (cls == [FakeResponseURLProtocol class]) {
            hasProtocol = YES;
            break;
        }
    }
    
    if (!hasProtocol) {
        [protocols insertObject:[FakeResponseURLProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    
    return config;
}

%end

// ==================== 初始化 ====================
__attribute__((constructor))
static void initializeFakeResponseProtocol() {
    [NSURLProtocol registerClass:[FakeResponseURLProtocol class]];
    NSLog(@"[Init] FakeResponseURLProtocol registered");
}