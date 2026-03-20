#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - 🎯 目标URL
static NSString *targetURL = @"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate";

#pragma mark - NSURLSession Hook

%hook NSURLSession

// 拦截 NSURLSession 的 dataTaskWithRequest 方法
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;

    // 只拦截目标 URL
    if ([url isEqualToString:targetURL]) {
        [HookLogger log:@"🔥 拦截目标 URL 请求: %@", url];

        // 创建伪造的 JSON 响应数据
        NSDictionary *fakeResponseDict = @{
            @"sing": [NSNull null],
            @"data": [NSNull null],
            @"code": @0,
            @"message": @"请求成功",
            @"success": @YES,
            @"skey": [NSNull null],
            @"timestamp": @1773899566825
        };

        // 将字典转为 NSData
        NSData *fakeResponseData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:nil];

        // 创建伪造的响应体
        NSURLResponse *fakeResponse = [[NSURLResponse alloc] initWithURL:request.URL
                                                               MIMEType:@"application/json"
                                                  expectedContentLength:fakeResponseData.length
                                                       textEncodingName:@"utf-8"];

        // 创建并返回伪造的 task
        NSURLSessionDataTask *fakeTask = [[NSURLSessionDataTask alloc] init];
        [fakeTask setValue:fakeResponse forKey:@"response"];
        [fakeTask setValue:fakeResponseData forKey:@"data"];

        [HookLogger log:@"🔥 返回伪造的响应数据: %@", fakeResponseDict];
        return fakeTask;
    }

    // 如果不拦截目标 URL，调用原始方法
    return %orig;
}

%end

#pragma mark - SSL 绕过

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    NSURLCredential *cred =
    [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];

    completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
}

%end

#pragma mark - ctor

%ctor {
    NSLog(@"🚀 Hook Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [HookLogger initUI];
        [HookLogger keepAlive];
        [HookLogger log:@"✅ UI Ready"];
    });
}