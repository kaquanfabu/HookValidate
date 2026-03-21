#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
static BOOL isTargetRequest(NSURLRequest *req) {
    if (!req || !req.URL) return NO;
    NSString *urlString = req.URL.absoluteString;
    // 这里匹配你抓包看到的接口路径
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    // 1. 判断是否是目标接口
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 命中目标接口: %@", request.URL.absoluteString);

        // 2. 定义新的回调处理逻辑
        void (^newCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *originalData, NSURLResponse *originalResponse, NSError *error) {
            
            // 安全检查：防止 completionHandler 为空
            if (!completionHandler) return;

            // --- 构造伪造的 JSON 数据 ---
            // 关键点：data 改为 {} 防止空指针崩溃
            // 关键点：timestamp 使用当前时间，防止校验过期
            long long currentTimestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
            
            NSString *jsonStr = [NSString stringWithFormat:
                                 @"{\"sing\":null,"
                                 @"\"data\":null,"
                                 @"\"code\":0,"
                                 @"\"message\":\"请求成功\","
                                 @"\"success\":true,"
                                 @"\"skey\":null,"
                                 @"\"timestamp\":%lld}", currentTimestamp];

            NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
            
            if (!fakeData) {
                // 如果数据构造失败，回退到原始逻辑
                completionHandler(originalData, originalResponse, error);
                return;
            }

            // --- 构造新的 Response (清洗头部) ---
            // 我们重新构造一个干净的 Response，只保留必要的字段
            // 这样做可以彻底移除 Content-Encoding: gzip 和 X-Content-Type-Options
            NSDictionary *cleanHeaders = @{
                @"Content-Type": @"application/json; charset=utf-8",
                @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)fakeData.length]
            };

            NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc]
                                               initWithURL:request.URL
                                               statusCode:200
                                               HTTPVersion:@"HTTP/1.1"
                                               headerFields:cleanHeaders];

            // --- 在主线程回调 ---
            // 确保 UI 更新在主线程进行，防止线程安全问题
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] ✅ 注入成功: %@", jsonStr);
                completionHandler(fakeData, fakeResponse, nil);
            });
        };

        // 3. 执行原始方法，但传入我们修改后的回调
        NSURLSessionDataTask *task = %orig(request, newCompletion);
        
        if (task) {
            [task resume];
        }
        return task;
    }

    // 4. 非目标请求，直接走原始逻辑
    return %orig(request, completionHandler);
}

%end
