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
            // 注意：我们不能简单地用 headerFields:@{...}，因为这样会丢失服务器原有的其他头信息
            // 我们需要基于原始的 Response 进行修改

            NSHTTPURLResponse *originalHTTPResponse = (NSHTTPURLResponse *)originalResponse;
            NSMutableDictionary *mutableHeaders = [originalHTTPResponse.allHeaderFields mutableCopy];

            // --- 核心修改点 ---
            // 移除 Content-Encoding，防止系统尝试解压我们的明文数据
            [mutableHeaders removeObjectForKey:@"Content-Encoding"];
            // 确保 Content-Length 是正确的
            [mutableHeaders setObject:[NSString stringWithFormat:@"%lu", (unsigned long)fakeData.length] forKey:@"Content-Length"];
            // 确保 Content-Type 正确
            [mutableHeaders setObject:@"application/json; charset=utf-8" forKey:@"Content-Type"];

            NSHTTPURLResponse *newResponse = [[NSHTTPURLResponse alloc]
                initWithURL:request.URL
                statusCode:200
                HTTPVersion:@"HTTP/1.1"
                headerFields:mutableHeaders];

            // --- 4. 异步打印日志 ---
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 拦截并修改返回: %@", jsonStr);
            });

            // 调用完成回调
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
