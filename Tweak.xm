#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 解压（修复内存问题）

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;
    
    // 初始化 z_stream
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    
    // 15 + 32 表示自动检测 gzip 或 zlib 头
    if (inflateInit2(&strm, 15 + 32) != Z_OK) {
        return nil;
    }
    
    // 预估解压后大小（通常压缩率 10:1，但保守估计 4:1）
    NSUInteger estimatedLength = data.length * 4;
    NSMutableData *decompressed = [NSMutableData dataWithLength:estimatedLength];
    
    int status;
    BOOL done = NO;
    
    while (!done) {
        // 检查空间是否足够
        if (strm.total_out >= decompressed.length) {
            decompressed.length += data.length; // 每次增加原数据大小
        }
        
        strm.next_out = (Bytef *)decompressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(decompressed.length - strm.total_out);
        
        status = inflate(&strm, Z_SYNC_FLUSH);
        
        if (status == Z_STREAM_END) {
            done = YES;
        } else if (status != Z_OK) {
            inflateEnd(&strm);
            NSLog(@"[Hook] Decompress error: %d", status);
            return nil;
        }
    }
    
    inflateEnd(&strm);
    decompressed.length = strm.total_out;
    return decompressed;
}

#pragma mark - gzip 压缩（修复内存问题）

NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;
    
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    // 15 + 16 表示 gzip 格式
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    
    // 预估压缩后大小（原大小 + 1KB 头信息）
    NSUInteger estimatedLength = data.length + 1024;
    NSMutableData *compressed = [NSMutableData dataWithLength:estimatedLength];
    
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    
    int status;
    
    do {
        if (strm.total_out >= compressed.length) {
            compressed.length += data.length; // 每次增加原数据大小
        }
        
        strm.next_out = (Bytef *)compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
        
        status = deflate(&strm, Z_FINISH);
        
    } while (status == Z_OK);
    
    deflateEnd(&strm);
    
    if (status != Z_STREAM_END) {
        NSLog(@"[Hook] Compress error: %d", status);
        return nil;
    }
    
    compressed.length = strm.total_out;
    return compressed;
}

#pragma mark - 判断gzip

BOOL isGzip(NSHTTPURLResponse *response) {
    NSString *encoding = response.allHeaderFields[@"Content-Encoding"];
    return encoding && [encoding.lowercaseString containsString:@"gzip"];
}

#pragma mark - 目标URL判断

BOOL isTarget(NSURLRequest *req) {
    if (!req.URL) return NO;
    NSString *urlString = req.URL.absoluteString;
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 构造假数据

NSData *buildFakeData() {
    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    
    NSDictionary *fake = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(timestamp)
    };
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fake options:0 error:&error];
    
    if (error) {
        NSLog(@"[Hook] JSON serialization error: %@", error);
        return [NSData data];
    }
    
    return jsonData;
}

#pragma mark - 安全的 Block 拷贝辅助函数

typedef void (^CompletionHandlerType)(NSData *, NSURLResponse *, NSError *);

static CompletionHandlerType createSafeHandler(CompletionHandlerType originalHandler, NSURLRequest *request) {
    // 拷贝 request 到堆上
    NSURLRequest *copiedRequest = [request copy];
    
    // 创建并返回新的 block（自动拷贝到堆上）
    CompletionHandlerType newHandler = [^(NSData *data, NSURLResponse *response, NSError *error) {
        @autoreleasepool {
            if (!isTarget(copiedRequest)) {
                originalHandler(data, response, error);
                return;
            }
            
            NSLog(@"[Hook] Intercepting response for target URL");
            
            // 构建假数据
            NSData *newData = buildFakeData();
            
            // 检查是否需要 gzip 压缩
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (isGzip(httpResponse)) {
                    NSData *compressed = gzipCompress(newData);
                    if (compressed) {
                        newData = compressed;
                        NSLog(@"[Hook] Compressed response: %lu -> %lu bytes", 
                              (unsigned long)newData.length, (unsigned long)compressed.length);
                    }
                }
            }
            
            // 调用原始 handler（在主线程或原线程）
            originalHandler(newData, response, error);
        }
    } copy]; // 显式 copy 到堆上
    
    return newHandler;
}

#pragma mark - NSURLSession Hook

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    
    // 创建安全的 handler
    CompletionHandlerType safeHandler = createSafeHandler(completionHandler, request);
    
    // 调用原始方法
    return %orig(request, safeHandler);
}

%end

#pragma mark - 安全的 Delegate 模式 Hook

%hook NSURLSessionDataTask

// 使用更安全的方式处理 delegate 模式
- (void)setDelegate:(id)delegate {
    if (isTarget(self.currentRequest)) {
        NSLog(@"[Hook] Task with delegate for target URL");
    }
    %orig;
}

%end

%hook NSURLSessionTask

// 安全的 KVO 观察
- (void)setState:(NSURLSessionTaskState)state {
    %orig;
    
    if (state == NSURLSessionTaskStateCompleted) {
        // 使用异步处理避免阻塞
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleTaskCompletion];
        });
    }
}

- (void)handleTaskCompletion {
    @autoreleasepool {
        NSURLRequest *req = self.currentRequest;
        if (!isTarget(req)) return;
        
        // 获取响应
        NSURLResponse *response = self.response;
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
        
        NSLog(@"[Hook] Modifying task response data");
        
        // 构建新数据
        NSData *newData = buildFakeData();
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        
        if (isGzip(httpResp)) {
            NSData *compressed = gzipCompress(newData);
            if (compressed) {
                newData = compressed;
            }
        }
        
        // 尝试通过私有 API 设置响应数据（不保证成功）
        @try {
            // 先尝试设置 responseData
            Ivar responseDataIvar = class_getInstanceVariable([self class], "_responseData");
            if (responseDataIvar) {
                object_setIvar(self, responseDataIvar, newData);
            }
            
            // 也尝试设置 _responseDataForCache
            Ivar cacheDataIvar = class_getInstanceVariable([self class], "_responseDataForCache");
            if (cacheDataIvar) {
                object_setIvar(self, cacheDataIvar, newData);
            }
        } @catch (NSException *exception) {
            NSLog(@"[Hook] Failed to set response data: %@", exception);
        }
    }
}

%end

#pragma mark - NSURLConnection Hook

%hook NSURLConnection

+ (void)sendAsynchronousRequest:(NSURLRequest *)request 
                          queue:(NSOperationQueue *)queue 
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    
    if (isTarget(request)) {
        NSLog(@"[Hook] Intercepting NSURLConnection request");
        
        void (^newHandler)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *response, NSData *data, NSError *error) {
            @autoreleasepool {
                NSData *newData = buildFakeData();
                
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                    if (isGzip(httpResp)) {
                        NSData *compressed = gzipCompress(newData);
                        if (compressed) newData = compressed;
                    }
                }
                
                handler(response, newData, error);
            }
        };
        
        %orig(request, queue, newHandler);
        return;
    }
    
    %orig(request, queue, handler);
}

+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    if (isTarget(request)) {
        NSLog(@"[Hook] Intercepting NSURLConnection delegate request");
        // 可以在这里添加自定义 delegate 拦截
    }
    return %orig(request, delegate);
}

%end

#pragma mark - 构造函数

%ctor {
    @autoreleasepool {
        NSLog(@"[Hook] Network hook loaded successfully");
        
        // 注册内存警告通知
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            NSLog(@"[Hook] Received memory warning");
        }];
    }
}

%dtor {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"[Hook] Network hook unloaded");
}