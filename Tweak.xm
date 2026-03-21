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

    // 目标请求判断
    if (!isTarget(request)) {
        return %orig(request, completionHandler);
    }

    NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);
    NSLog(@"[Hook] 请求头: %@", request.allHTTPHeaderFields);

    // ✅ 保存原始 completionHandler
    void (^origHandler)(NSData *, NSURLResponse *, NSError *) = completionHandler;

    // ✅ 创建新的 completionHandler
    void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {

        NSLog(@"[Hook] 原始回调触发");

        // 如果发生错误，直接返回原数据
        if (error) {
            NSLog(@"[Hook] 错误: %@", error.localizedDescription);
            if (origHandler) origHandler(data, response, error);
            return;
        }

        // 打印原始返回数据（调试用）
        if (data) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[Hook] 原始返回: %@", str);
        }

        // ✅ 替换返回数据
        NSData *newData = buildJSON();
        if (!newData) {
            newData = data; // 如果替换失败，回退到原始数据
        }

        NSLog(@"[Hook] ✅ 返回伪造 JSON");

        // 调用原始 completionHandler，返回修改后的数据
        if (origHandler) {
            origHandler(newData, response, error);
        }
    };

    // ✅ 调用原始 dataTask，使用新的 completionHandler
    NSURLSessionDataTask *task = %orig(request, newHandler);

    return task;
}

%end