#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>
#import <Alamofire/Alamofire.h>

#pragma mark - 🎯 目标URL

static NSString *targetURL = @"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate";

#pragma mark - Alamofire SessionDelegate Hook

%hook Alamofire.SessionDelegate

// 拦截 Alamofire SessionDelegate 中的 task 相关方法
- (void)session:(NSURLSession *)session
task:(NSURLSessionTask *)task
didReceiveResponse:(NSURLResponse *)response
completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    // 获取请求 URL 和响应信息
    NSString *url = task.currentRequest.URL.absoluteString;

    if ([url isEqualToString:targetURL]) {
        [HookLogger log:@"🔥 Alamofire 请求命中 %@", url];

        // 创建伪造的 JSON 数据
        NSDictionary *fakeResponseDict = @{
            @"sing": [NSNull null],
            @"data": [NSNull null],
            @"code": @0,
            @"message": @"请求成功",
            @"success": @YES,
            @"skey": [NSNull null],
            @"timestamp": @1773899566825
        };

        // 将字典转为 JSON 数据
        NSData *fakeResponseData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:nil];
        
        // 创建一个伪造的响应体
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSHTTPURLResponse *newResponse = [[NSHTTPURLResponse alloc] initWithURL:task.currentRequest.URL
                                                                     statusCode:200
                                                                    HTTPVersion:@"1.1"
                                                                   headerFields:nil];

        // 通过 completionHandler 返回伪造的响应和数据
        completionHandler(NSURLSessionResponseAllow);
        
        // 这里你可以使用伪造的数据继续进行后续处理
        [HookLogger log:@"🔥 返回伪造的响应数据: %@", fakeResponseDict];
        [self handleFakeData:fakeResponseData forTask:task response:newResponse];
    }

    // 如果不拦截目标 URL，调用原始方法
    %orig;
}

// 处理伪造的数据并将其返回给响应
- (void)handleFakeData:(NSData *)fakeData forTask:(NSURLSessionTask *)task response:(NSURLResponse *)response {
    // 模拟返回伪造的响应体
    NSURLSessionDataTask *fakeTask = [[NSURLSessionDataTask alloc] init];
    [fakeTask setValue:response forKey:@"response"];
    [fakeTask setValue:fakeData forKey:@"data"];
    
    // 可以在这里进一步处理伪造的任务（例如在日志中输出或直接处理）
    [HookLogger log:@"🔥 伪造的数据: %@", [[NSString alloc] initWithData:fakeData encoding:NSUTF8StringEncoding]];
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