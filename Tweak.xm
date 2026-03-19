#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 只拦截指定 URL 的请求
    if ([request.URL.absoluteString containsString:@"https://wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
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
    NSHTTPURLResponse *fakeResponseObj = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                                      statusCode:200
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{@"Content-Type": @"application/json"}];

    [self.client URLProtocol:self didReceiveResponse:fakeResponseObj cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:fakeData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end