#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    NSLog(@"[Hook] 检查 URL: %@", urlString);  // 打印请求 URL，用于调试

    // 使用更精确的匹配方式，确保只匹配特定请求
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    // 1. 判断是否命中目标接口
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 2. 创建新的处理回调 (用来替换原始回调)
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            // --- 错误处理 ---
            // 如果请求本身出错，直接回调原始数据，不进行篡改
            if (error) {
                NSLog(@"[Hook] ⚠️ 请求发生错误，返回原始错误信息: %@", error);
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // --- 打印原始数据 ---
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 📄 原始返回数据: %@", str);
            }

            // --- 构造伪造数据 ---
            NSString *modifiedResponseStr = @"{ \
                \"sing\" : null, \
                \"data\" : { \
                    \"validateItem\" : \"0,1,2,3,4\" \
                }, \
                \"code\" : 0, \
                \"message\" : \"请求成功\", \
                \"success\" : true, \
                \"skey\" : null, \
                \"timestamp\" : 1774093881179 \
            }";
            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

            // 主线程打印修改后的数据（仅用于调试查看）
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 修改后的返回: %@", modifiedResponseStr);
            });

            // --- 返回伪造数据 ---
            // 将伪造的 newData 传给原本的 completionHandler
            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        // 3. 【关键修复】使用 %orig 执行原始请求，但传入我们的 newHandler
        // 这样既发起了真实的网络请求，又避免了重新创建 Task 导致的无限递归
        NSURLSessionDataTask *task = %orig(request, newHandler);
        
        // 4. 启动任务
        [task resume];

        return task;
    }

    // 5. 如果未命中目标，直接执行原始逻辑
    return %orig(request, completionHandler);
}

%end
