#import <Foundation/Foundation.h>

#pragma mark - 构造返回 JSON
static NSData *buildJSON() {
    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @1773899566825
    };

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {

    NSString *url = request.URL.absoluteString;

    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        // 构造假返回
        NSData *fakeData = buildJSON();
        NSHTTPURLResponse *fakeResp = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                  statusCode:200
                                                                 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Content-Type":@"application/json"}];

        // 调度到主队列，模拟异步返回
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(fakeData, fakeResp, nil);
        });

        // 创建一个假的NSURLSessionDataTask任务，立即取消它
        NSURLSessionDataTask *dummyTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {}];
        [dummyTask cancel]; // 确保不发送请求
        return dummyTask;   // 返回假的任务
    }

    // 默认返回真实的任务
    return %orig(request, completionHandler);
}

%end