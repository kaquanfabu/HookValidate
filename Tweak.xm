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

        // --- 1. 保存原始的 completionHandler ---
        __block typeof(completionHandler) originalCompletion = completionHandler;

        // --- 2. 定义新的回调 ---
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            // 伪造数据
            NSString *modifiedResponseStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"timestamp\":1774093881179,\"data\":null}";
            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

            // 异步打印
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 拦截并修改返回: %@", modifiedResponseStr);
            });

            // 调用原始回调，传入伪造数据
            if (originalCompletion) {
                originalCompletion(newData, response, nil);
            }
        };

        // --- 3. Hook 代理回调 ---
        // 检查并替换代理回调方法
        if ([self respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            // Logos 风格的 Hook：直接覆盖原方法
            %c(self).instanceMethodForSelector(@selector(URLSession:task:didCompleteWithError:)) = ^(id self, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
                NSLog(@"[Hook] 🛡️ 代理回调被拦截: %@", task.originalRequest.URL);
                // 关键：使用 %orig 调用原始的代理回调逻辑
                %orig(session, task, nil); // 传入 nil 表示任务“成功”完成
            };
        }

        // --- 4. 执行原始逻辑 ---
        NSURLSessionDataTask *task = %orig(request, newHandler);

        if (task) {
            [task resume];
        }

        return task;
    }

    // 非目标请求，走原始逻辑
    return %orig(request, completionHandler);
}

%end
