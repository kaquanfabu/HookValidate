#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 自定义 NSURLProtocol

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([request.URL.absoluteString containsString:@"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        if ([NSURLProtocol propertyForKey:@"CustomURLProtocolHandled" inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"CustomURLProtocolHandled" inRequest:mutableRequest];

    NSDictionary *fakeResponse = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @1773924691881
    };

    NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponse options:0 error:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{
        @"Content-Type": @"application/json",
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)fakeData.length]
    }];

    // 保证回调在主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:fakeData];
        [self.client URLProtocolDidFinishLoading:self];
    });
}

- (void)stopLoading {}

@end

#pragma mark - 注册 NSURLProtocol

%hook UIApplication

- (BOOL)finishLaunching {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSURLProtocol registerClass:[CustomURLProtocol class]];
    });
    return %orig;
}

%end

#pragma mark - 安全 Hook Alamofire dataTask

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    if ([request.URL.absoluteString containsString:@"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        // 构建 JSON 响应
        NSDictionary *fakeResponse = @{
            @"sing": [NSNull null],
            @"data": [NSNull null],
            @"code": @0,
            @"message": @"请求成功",
            @"success": @YES,
            @"skey": [NSNull null],
            @"timestamp": @1773924691881
        };
        NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponse options:0 error:nil];

        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                  statusCode:200
                                                                 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{
            @"Content-Type": @"application/json",
            @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)fakeData.length]
        }];

        // 返回数据，延迟异步调用 completionHandler，避免闪退
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(fakeData, response, nil);
        });

        // 这里仍返回原始的 dataTask，避免 Alamofire 崩溃
        return %orig(request, completionHandler);
    }

    return %orig(request, completionHandler);
}

%end