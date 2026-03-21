#import <Foundation/Foundation.h>

#pragma mark - 构造 JSON（你可以后面再改结构）
NSData *buildJSON() {
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

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

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

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // ✅ 防递归
        if ([request valueForHTTPHeaderField:@"X-Hooked"]) {
            NSLog(@"[Hook] 跳过递归请求: %@", request.URL.absoluteString);
            return %orig(request, completionHandler);
        }

        // 拷贝请求以修改它
        NSMutableURLRequest *req = [request mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:@"X-Hooked"];  // 防止递归

        // 创建新的处理回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            // 打印原始数据
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 原始返回: %@", str);
            }

            // 如果请求出错，返回原数据
            if (error) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // 替换数据
            NSData *newData = buildJSON();

            // 打印替换后的数据
            NSLog(@"[Hook] 修改后的返回: %@", [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]);

            // 返回修改后的数据
            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        // 执行原始请求，并传递新的回调
        return %orig(req, newHandler);
    }

    return %orig(request, completionHandler);
}

%end