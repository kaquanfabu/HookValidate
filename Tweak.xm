#import <Foundation/Foundation.h>

#pragma mark - 构造 JSON
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

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!jsonData) {
        NSLog(@"[Hook] 构建 JSON 数据失败");
    }
    return jsonData;
}

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);
        NSLog(@"[Hook] 请求头: %@", request.allHTTPHeaderFields);

        // ✅ 直接调用原始网络任务，不替换 completionHandler
        NSURLSessionDataTask *task = %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSLog(@"[Hook] 原始回调触发");

            // 如果发生错误，直接返回
            if (error) {
                NSLog(@"[Hook] 错误: %@", error.localizedDescription);
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // ✅ 替换返回数据
            NSData *newData = buildJSON();
            if (!newData) {
                newData = data; // 失败回退原数据
            }

            NSLog(@"[Hook] 返回伪造 JSON");

            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        });

        return task;
    }

    return %orig(request, completionHandler);
}

%end