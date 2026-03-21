#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
static BOOL isTargetRequest(NSURLRequest *req) {
    if (!req || !req.URL) return NO;
    NSString *urlString = req.URL.absoluteString;
    // 这里匹配你抓包看到的接口路径
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSessionTask

- (void)resume {
    // 1. 获取当前任务的原始请求
    NSURLRequest *request = [self originalRequest];
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 拦截到任务 resume: %@", request.URL.absoluteString);

        // 2. 构造返回数据（防崩溃处理）
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
        NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];

        // 3. 构造响应头（关键：清洗不兼容的 Header）
        NSURLResponse *response = [[NSHTTPURLResponse alloc]
                                   initWithURL:request.URL
                                   statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                   headerFields:@{
                                       @"Content-Type": @"application/json; charset=utf-8",
                                       // 移除可能引起解码错误的字段
                                       @"Content-Encoding": @"identity"
                                   }];

        // 4. 异步调用回调（防止主线程阻塞）
        dispatch_async(dispatch_get_main_queue(), ^{
            // 调用原始的 completionHandler
            [self didReceiveData:fakeData response:response error:nil];
        });
    } else {
        // 非目标请求，执行原逻辑
        %orig;
    }
}

%end
