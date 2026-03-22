#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// ==================== 1. 定义关联对象 Key ====================
static char kIsTargetTaskKey;
static char kFakeDataKey;
static char kOriginalCompletionHandlerKey;

// ==================== 2. 工具函数 ====================
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // 添加更详细的日志
    NSLog(@"[Hook] 检查请求: %@", urlStr);
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
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
    do {
        if (strm.total_out >= compressed.length) {
            [compressed increaseLengthBy:16384];
        }
        strm.next_out = ((Bytef *)compressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
    } while (deflate(&strm, Z_FINISH) == Z_OK);
    
    deflateEnd(&strm);
    [compressed setLength:strm.total_out];
    return compressed;
}

static NSData *fakeJsonData() {
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
        return nil;
    }
    
    return gzipData(jsonData);
}

// ==================== 3. 自定义 URLProtocol ====================
@interface FakeResponseURLProtocol : NSURLProtocol
@end

@implementation FakeResponseURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 只拦截目标请求
    if (isTargetRequest(request)) {
        NSLog(@"[Protocol] 🎯 拦截到目标请求: %@", request.URL);
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSLog(@"[Protocol] 📡 开始返回伪造数据");
    
    // 获取请求
    NSURLRequest *request = self.request;
    id<NSURLProtocolClient> client = self.client;
    
    // 构造伪造的响应头
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] 
        initWithURL:request.URL 
        statusCode:200 
        HTTPVersion:@"HTTP/1.1" 
        headerFields:@{
            @"Content-Type": @"application/json",
            @"Content-Encoding": @"gzip",
            @"Content-Length": @(fakeJsonData().length).stringValue
        }];
    
    // 发送响应头
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    
    // 发送数据
    NSData *fakeData = fakeJsonData();
    if (fakeData) {
        [client URLProtocol:self didLoadData:fakeData];
        NSLog(@"[Protocol] ✅ 已发送伪造数据，长度: %lu", (unsigned long)fakeData.length);
    } else {
        NSLog(@"[Protocol] ❌ 伪造数据生成失败");
    }
    
    // 完成加载
    [client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 无需额外操作
}

@end

// ==================== 4. 方法 Swizzling 辅助 ====================
static void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(class,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(class,
                           swizzledSelector,
                           method_getImplementation(originalMethod),
                           method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

// ==================== 5. 处理 delegate 模式 ====================
@interface FakeDataDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, weak) id<NSURLSessionDataDelegate> originalDelegate;
@property (nonatomic, assign) BOOL hasSentFakeData;
@end

@implementation FakeDataDelegate

- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate {
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
    
    // 检查是否需要伪造响应
    if (!self.hasSentFakeData && isTargetRequest(dataTask.originalRequest)) {
        NSLog(@"[Delegate] 🎯 拦截响应，返回伪造数据");
        
        // 构造伪造响应
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
            initWithURL:response.URL
            statusCode:200
            HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Content-Type": @"application/json", @"Content-Encoding": @"gzip"}];
        
        // 转发伪造响应
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
    } else {
        // 转发原始响应
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
            [self.originalDelegate URLSession:session
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
    
    // 检查是否需要伪造数据
    if (!self.hasSentFakeData && isTargetRequest(dataTask.originalRequest)) {
        self.hasSentFakeData = YES;
        
        NSData *fakeData = fakeJsonData();
        if (fakeData) {
            NSLog(@"[Delegate] ✅ 注入伪造数据，长度: %lu", (unsigned long)fakeData.length);
            
            if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
                [self.originalDelegate URLSession:session
                                         dataTask:dataTask
                                   didReceiveData:fakeData];
            }
            return;
        }
    }
    
    // 转发原始数据
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [self.originalDelegate URLSession:session
                                 dataTask:dataTask
                           didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    
    // 检查是否已经发送伪造数据
    if (!self.hasSentFakeData && isTargetRequest(task.originalRequest)) {
        NSLog(@"[Delegate] ⚠️ 未收到数据回调，在完成时注入");
        self.hasSentFakeData = YES;
        
        NSData *fakeData = fakeJsonData();
        if (fakeData && [self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [self.originalDelegate URLSession:session
                                     dataTask:(NSURLSessionDataTask *)task
                               didReceiveData:fakeData];
        }
        
        // 完成时不传递错误
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:nil];
        }
    } else {
        // 转发原始完成
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
        }
    }
}

// 转发其他必要的方法
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

// ==================== 6. Hook NSURLSession 的 delegate ====================
%hook NSURLSession

- (void)setDelegate:(id<NSURLSessionDelegate>)delegate {
    // 如果是需要拦截的 session，包装 delegate
    // 这里简单处理：不对 session 的 delegate 进行包装，因为影响面太大
    %orig;
}

// Hook dataTask 方法以标记目标任务
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig(request);
    
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 标记目标任务: %@", request.URL);
        objc_setAssociatedObject(task, &kIsTargetTaskKey, @YES, OBJC_ASSOCIATION_RETAIN);
    }
    
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    // 对于 completionHandler 模式，直接替换回调
    if (isTargetRequest(request) && completionHandler) {
        NSLog(@"[Hook] 🎯 拦截 completionHandler 模式请求");
        
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *fakeData = fakeJsonData();
            if (fakeData) {
                NSLog(@"[Hook] ✅ 使用伪造数据替换原始回调");
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

// ==================== 7. 自动注册 Protocol ====================
__attribute__((constructor))
static void initializeFakeResponseProtocol() {
    NSLog(@"[Init] 🚀 初始化网络拦截器");
    
    // 注册 URLProtocol
    [NSURLProtocol registerClass:[FakeResponseURLProtocol class]];
    
    NSLog(@"[Init] ✅ URLProtocol 注册完成");
}