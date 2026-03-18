#import <Foundation/Foundation.h>

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler
{
    NSString *url = request.URL.absoluteString;

    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error)
        {

            NSDictionary *fakeJson = @{
                @"sing":[NSNull null],
                @"data":[NSNull null],
                @"code":@0,
                @"message":@"请求成功",
                @"success":@YES,
                @"skey":[NSNull null],
                @"timestamp":@1773846248358
            };

            NSData *jsonData =
            [NSJSONSerialization dataWithJSONObject:fakeJson
                                            options:0
                                              error:nil];

            // 构造新的 HTTP 响应
            NSHTTPURLResponse *newResponse =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:@{
                                          @"Content-Type":@"application/json"
                                      }];

            completionHandler(jsonData, newResponse, nil);
        };

        return %orig(request,newHandler);
    }

    return %orig(request,completionHandler);
}

%end
