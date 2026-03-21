#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    NSLog(@"[Hook] 检查 URL: %@", urlString);
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 伪造响应数据
NSData *createMockData() {
    // 修复 1: 加上 @ 前缀，使用紧凑 JSON，data 设为空字典 {} 防止崩溃
    NSString *jsonStr = @"{\"sing\":null,\"data\":{},\"code\":0,\"message\":\"请求成功\",\"success\":true,\"skey\":null,\"timestamp\":1773899566825}";
    return [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
}

%hook NSURLSession

// ==================== Hook POST 请求 ====================
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                   uploadData:(NSData *)bodyData
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中 POST 接口: %@", request.URL.absoluteString);

        // 获取伪造数据
        NSData *mockData = createMockData();

        // 模拟异步返回 (延迟 0.5 秒)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 直接调用回调返回数据，response 和 error 传 nil
            if (completionHandler) {
                completionHandler(mockData, nil, nil);
            }
        });

        // 修复 2: 使用 alloc/init 代替 new，避免 iOS 13+ 废弃警告
        NSURLSessionDataTask *task = [[NSURLSessionDataTask alloc] init];
        return task;
    }

    // 未命中，执行原始逻辑
    return %orig(request, bodyData, completionHandler);
}

// ==================== Hook GET 请求 ====================
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中 GET 接口: %@", request.URL.absoluteString);

        // 获取伪造数据
        NSData *mockData = createMockData();

        // 模拟异步返回
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (completionHandler) {
                completionHandler(mockData, nil, nil);
            }
        });

        // 修复 2: 使用 alloc/init
        NSURLSessionDataTask *task = [[NSURLSessionDataTask alloc] init];
        return task;
    }

    // 未命中，执行原始逻辑
    return %orig(request, completionHandler);
}

%end
