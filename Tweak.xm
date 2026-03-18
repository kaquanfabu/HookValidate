#import <Foundation/Foundation.h>

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;

    if ([url containsString:@"/nwgt/web/api/v1/menu/validate"])
    {
        NSLog(@"[HOOK] intercept validate");
        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSString *fakeJson =
    @"{"
    "\"sing\":null,"
    "\"data\":null,"
    "\"code\":0,"
    "\"message\":\"请求成功\","
    "\"success\":true,"
    "\"skey\":null,"
    "\"timestamp\":1773846248358"
    "}";

    NSData *data = [fakeJson dataUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *headers =
    @{
        @"content-type": @"application/json;charset=UTF-8",
        @"connection": @"keep-alive"
    };

    NSHTTPURLResponse *response =
    [[NSHTTPURLResponse alloc]
        initWithURL:self.request.URL
        statusCode:200
        HTTPVersion:@"HTTP/1.1"
        headerFields:headers];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading
{
}

@end