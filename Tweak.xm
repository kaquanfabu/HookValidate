#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    // 使用 containsString 足够，但如果 URL 参数多，建议用 NSURLComponents 或正则更精准
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 定义新的回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = 
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            // --- 1. 错误处理：如果原始请求失败，直接返回错误 ---
            if (error) {
                NSLog(@"[Hook] ⚠️ 原始请求出错: %@", error);
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // --- 2. 构造伪造数据 ---
            // 注意：timestamp 使用了固定的 1774093881179，确保与你截图中的时间一致
            NSString *modifiedResponseStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"timestamp\":1774093881179,\"data\":null}";

            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];
            
            // --- 3. 打印日志 ---
            // 异步打印，避免阻塞网络线程
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 拦截并修改返回: %@", modifiedResponseStr);
            });

            // --- 4. 核心修复：必须调用原始回调，否则 App 会卡住等待响应 ---
            // 即使我们修改了数据，也必须把控制权交还给 App
            if (completionHandler) {
                // 注意：这里我们传入 newData 替代了原始的 data
                completionHandler(newData, response, nil); 
                // 注意：这里将 error 设为 nil，因为我们伪造了成功响应
            }
        };

        // --- 5. 执行原始逻辑并获取任务对象 ---
        NSURLSessionDataTask *task = %orig(request, newHandler);

        // --- 6. 关键：必须 resume，否则任务不会开始 ---
        if (task) {
            [task resume];
        } else {
            NSLog(@"[Hook] ❌ 任务创建失败");
        }

        return task; // 必须返回任务对象
    }

    // 如果不是目标请求，走原始逻辑
    return %orig(request, completionHandler);
}

%end
