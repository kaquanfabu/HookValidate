#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    NSLog(@"[Hook] 检查 URL: %@", urlString);
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 伪造响应数据
NSData *createMockData() {
    // 使用紧凑格式，去掉多余空格和换行
    // 修正后的 Hook 代码
NSString *modifiedResponseStr = "{\"sing\":null,\"data\":null,\"code\":0,\"message\":\"请求成功\",\"success\":true,\"skey\":null,\"timestamp\":1773899566825}";

// 将字符串转换为 NSData
NSData *modifiedResponseData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

// 调用原始方法或直接返回修改后的数据
// ...
";
    return [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
}

%hook NSURLSession

// ==================== Hook 1: 处理 POST 请求 (关键修复) ====================
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                                   uploadData:(NSData *)bodyData
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中 POST 接口: %@", request.URL.absoluteString);

        // 构造伪造数据
        NSData *mockData = createMockData();

        // 打印原始和伪造数据
        NSString *origStr = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
        NSLog(@"[Hook] 📄 原始请求体: %@", origStr);
        NSLog(@"[Hook] 🔓 伪造响应数据: %@", [[NSString alloc] initWithData:mockData encoding:NSUTF8StringEncoding]);

        // 模拟异步返回
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            completionHandler(mockData, [NSHTTPURLResponse new], nil);
        });

        // 创建并返回一个空的 Task，防止崩溃
        NSURLSessionDataTask *task = [NSURLSessionDataTask new];
        [task resume];
        return task;
    }

    // 未命中，执行原始逻辑
    return %orig(request, bodyData, completionHandler);
}

// ==================== Hook 2: 处理 GET 请求 (备用) ====================
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中 GET 接口: %@", request.URL.absoluteString);

        // 构造伪造数据
        NSData *mockData = createMockData();

        // 模拟异步返回
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            completionHandler(mockData, [NSHTTPURLResponse new], nil);
        });

        // 创建并返回一个空的 Task，防止崩溃
        NSURLSessionDataTask *task = [NSURLSessionDataTask new];
        [task resume];
        return task;
    }

    // 未命中，执行原始逻辑
    return %orig(request, completionHandler);
}

%end
