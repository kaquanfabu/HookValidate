#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 自定义 NSURLProtocol 拦截器

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 只拦截目标 URL
    if ([request.URL.absoluteString containsString:@"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        // 防止循环拦截
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
    // 标记已处理，防止死循环
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"CustomURLProtocolHandled" inRequest:mutableRequest];

    // 构建返回的 JSON 数据
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

    // 创建虚假的 HTTP 响应
    NSHTTPURLResponse *fakeResp = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"application/json"}];

    [self.client URLProtocol:self didReceiveResponse:fakeResp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:fakeData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 可在这里处理请求取消逻辑
}

@end

#pragma mark - Hook UIApplication 启动时注册 NSURLProtocol

%hook UIApplication

- (BOOL)finishLaunching {
    // 注册自定义 NSURLProtocol
    [NSURLProtocol registerClass:[CustomURLProtocol class]];

    return %orig;
}

%end

#pragma mark - Alamofire NSURLSession 拦截示例（可选）

// 如果你在内部直接使用 NSURLSession，可以这样 Hook Alamofire 的 SessionDelegate
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    // 检查目标 URL
    if ([request.URL.absoluteString containsString:@"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        // 构建自定义 JSON 响应
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

        // 创建虚拟 HTTP 响应
        NSHTTPURLResponse *fakeResp = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                  statusCode:200
                                                                 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Content-Type": @"application/json"}];

        // 直接返回响应
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(fakeData, fakeResp, nil);
        });

        return nil; // 不执行原始请求
    }

    return %orig(request, completionHandler);
}

%end