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
        NSLog(@"[Hook] 🎯 命中接口");

        // 直接拦截请求，不做防递归和标识的检查
        NSMutableURLRequest *req = [request mutableCopy];

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            // ✅ 打印原始返回（用于你后面对比结构）
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 原始返回: %@", str);
            }

            // ❗ 如果原本就失败，别乱改（避免逻辑炸）
            if (error) {
                NSLog(@"[Hook] 错误发生: %@", error.localizedDescription);
                if (completionHandler) {
                    completionHandler(data, response, error);  // 确保错误返回
                }
                return;
            }

            // ✅ 替换数据（只改这里！）
            NSData *newData = buildJSON();
            if (!newData) {
                NSLog(@"[Hook] 替换数据失败，返回原始数据");
                newData = data;  // 确保如果替换失败仍然返回原数据
            }

            // 确保返回数据
            if (completionHandler) {
                NSLog(@"[Hook] 返回数据");
                completionHandler(newData, response, error);  // 强制返回数据，避免没有数据返回
            } else {
                NSLog(@"[Hook] 没有调用completionHandler，检查是否调用正确");
            }
        };

        return %orig(req, newHandler);
    }

    return %orig(request, completionHandler);
}

%end