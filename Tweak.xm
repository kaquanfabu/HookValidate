#import <Foundation/Foundation.h>

#pragma mark - 构造 JSON
static NSData *buildJSON() {
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
static BOOL isTarget(NSURLRequest *req) {
    if (!req.URL) return NO;
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    // 非目标请求直接放行
    if (!isTarget(request)) {
        return %orig(request, completionHandler);
    }

    NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

    // ✅ 关键：先保存原始 handler
    void (^origHandler)(NSData *, NSURLResponse *, NSError *) = completionHandler;

    // ✅ 新 handler（只处理返回，不阻塞请求）
    void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {

        NSLog(@"[Hook] 原始回调触发");

        // 出错直接返回原数据
        if (error) {
            NSLog(@"[Hook] 错误: %@", error);
            if (origHandler) origHandler(data, response, error);
            return;
        }

        // 打印原始数据（调试用）
        if (data) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[Hook] 原始返回: %@", str);
        }

        // ✅ 替换返回
        NSData *newData = buildJSON();
        if (!newData) newData = data;

        NSLog(@"[Hook] ✅ 返回伪造数据");

        if (origHandler) {
            origHandler(newData, response, error);
        }
    };

    // ✅ 关键：调用原始方法（不会阻塞网络）
    return %orig(request, newHandler);
}

%end