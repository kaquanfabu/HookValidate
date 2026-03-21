#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 定义新的回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = 
        ^(NSData *data, NSURLResponse *originalResponse, NSError *error) {
            
            // --- 1. 错误处理 ---
            if (error) {
                NSLog(@"[Hook] ⚠️ 原始请求出错: %@", error);
                if (completionHandler) {
                    completionHandler(data, originalResponse, error);
                }
                return;
            }

            // --- 2. 构造伪造的 JSON 数据 ---
            NSString *jsonStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"data\":null}";
            NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];

            // --- 3. 关键修复：构造新的 Response ---
            // 原始的 originalResponse 可能是服务器返回的（包含 Gzip 或 Content-Length 为 0）
            // 我们必须创建一个新的 Response，告诉 App："我返回的是 JSON，长度是 xxx"
            
            // 获取原始请求的 URL
            NSURL *responseURL = request.URL;
            
            // 构造新的 HTTP Response
            NSHTTPURLResponse *newResponse = [[NSHTTPURLResponse alloc]
                initWithURL:responseURL
                statusCode:200
                HTTPVersion:@"HTTP/1.1"
                headerFields:@{
                    @"Content-Type": @"application/json; charset=utf-8",
                    @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)fakeData.length]
                }];

            // --- 4. 异步打印日志 ---
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 拦截并修改返回: %@", jsonStr);
            });

                completionHandler(fakeData, newResponse, nil);
            
        };

        // --- 6. 执行原始逻辑 ---
        NSURLSessionDataTask *task = %orig(request, newHandler);

        if (task) {
            [task resume];
        }

        return task;
    }

    // 不是目标请求，走原始逻辑
    return %orig(request, completionHandler);
}

%end
