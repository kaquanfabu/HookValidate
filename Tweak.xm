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
        // 伪造的 JSON 响应数据
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

        // 使用 dataTaskWithRequest 来创建任务
        NSURLSessionDataTask *fakeTask = [self dataTaskWithRequest:request];

        // 将伪造的数据作为响应返回
        [fakeTask setValue:fakeResponse forKey:@"response"];
        [fakeTask setValue:fakeResponseData forKey:@"data"];

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
    // 可以选择去掉日志部分，避免 `HookLogger` 错误。
}