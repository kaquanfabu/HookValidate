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

    // 1. 判断是否命中目标
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 2. 定义我们自己的回调处理逻辑
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            // --- 错误处理 ---
            if (error) {
                NSLog(@"[Hook] ⚠️ 请求出错，直接返回原始错误");
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // --- 打印原始数据 ---
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 📄 原始返回: %@", str);
            }

            // --- 构造伪造数据 ---
            // 去掉所有换行和空格，使用紧凑格式
            NSString *modifiedResponseStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"timestamp\":1774093881179,\"data\":null}";


            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 修改后的返回: %@", modifiedResponseStr);
            });

            // --- 执行原始回调，但传入伪造的数据 ---
            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        // ================= 核心修复区域 =================
        
        // 1. 调用 %orig 执行原始的网络请求逻辑，传入新的回调，并**接收返回的 Task 对象**
        // 注意：必须用 id 或 NSURLSessionDataTask * 接收返回值
        NSURLSessionDataTask *task = %orig(request, newHandler);
        
        // 2. 必须手动调用 resume，因为原始任务创建后是暂停状态
        if (task) {
            [task resume];
        } else {
            NSLog(@"[Hook] ❌ 任务创建失败，task 为 nil");
        }

        // 3. **必须返回** 这个 task 对象给调用者
        return task;
        
        // ==============================================
    }

    // 如果没有命中目标，直接执行原始逻辑并返回
    return %orig(request, completionHandler);
}

%end
