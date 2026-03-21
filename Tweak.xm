#import <Foundation/Foundation.h>

// 定义一个辅助方法来判断是否是目标 URL
static BOOL isTargetUrl(NSURL *url) {
    if (!url) return NO;
    NSString *urlStr = [url absoluteString];
    // 请将下面的字符串替换为你实际要拦截的接口路径
    return [urlStr containsString:@"/nwgt/web/api/v1/menu/validate"];
}

// --- 核心 Hook 代码 ---

%hook NSURLSession

// Hook 这个方法最稳妥，因为它直接拿到了 completionHandler
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    // 1. 判断是否是目标请求
    if (isTargetUrl(request.URL)) {
        NSLog(@"[Hook] 🎯 拦截并伪造响应: %@", request.URL);

        // 2. 构造 JSON 数据
        // 注意：data 改为了 {} 防止 App 解析 null 崩溃
        // timestamp 使用当前时间
        long long timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
        NSString *jsonStr = [NSString stringWithFormat:
                             @"{"
                             @"\"sing\":null,"
                             @"\"data\":{},"
                             @"\"code\":0,"
                             @"\"message\":\"请求成功\","
                             @"\"success\":true,"
                             @"\"skey\":null,"
                             @"\"timestamp\":%lld"
                             @"}", timestamp];

        // 3. 转为 Data
        NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];

        // 4. 构造 Response
        // 关键点：URL 必须和请求一致，否则 App 会校验失败
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:request.URL
                                                             MIMEType:@"application/json"
                                                expectedContentLength:[fakeData length]
                                                     textEncodingName:@"UTF-8"];

        // 5. 调用原始的 completionHandler 并传入假数据
        // 这一步会触发 App 的业务逻辑，让页面不再卡死
        void (^newCompletion)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *res, NSError *error) {
            completionHandler(fakeData, response, nil);
        };

        // 6. 调用父类方法，传入新的回调
        // 原始的 completionHandler 在这里被 newCompletion 替换了
        NSURLSessionDataTask *task = %orig(request, newCompletion);
        return task;
    }

    // 如果不是目标请求，执行原始逻辑
    return %orig;
}

%end
