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

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 核心 Hook（NSURLSession / Alamofire）
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {

        NSLog(@"[Hook] 🎯 命中接口");

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSData *json = buildJSON();

            NSDictionary *headers = @{
                @"Content-Type": @"application/json;charset=UTF-8"
                // ❌ 不要 gzip
            };

            NSHTTPURLResponse *resp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:headers];

            // ✅ 直接回调，不切线程
            completionHandler(json, resp, nil);
        };

        return %orig(request, newHandler);
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - SSL 绕过
%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {

        NSURLCredential *cred =
        [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];

        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    %orig(session, challenge, completionHandler);
}

%end

#pragma mark - NSURLConnection（兼容旧库，可选）
%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    if (isTarget(request)) return YES;
    return %orig;
}

%end