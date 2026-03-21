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
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {

        // ✅ 防递归
        if ([request valueForHTTPHeaderField:@"X-Hooked"]) {
            return %orig(request, completionHandler);
        }

        NSMutableURLRequest *req = [request mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:@"X-Hooked"];

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSLog(@"[Hook] 🎯 命中接口");

            // ✅ 打印原始返回（用于你后面对比结构）
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 原始返回: %@", str);
            }

            // ❗ 如果原本就失败，别乱改（避免逻辑炸）
            if (error) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // ✅ 替换数据（只改这里！）
            NSData *newData = buildJSON();

            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        return %orig(req, newHandler);
    }

    return %orig(request, completionHandler);
}

%end