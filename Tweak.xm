#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FloatingLogView.h"

#pragma mark - URL 匹配函数
BOOL isTarget(NSURLRequest *req) {
    NSString *url = req.URL.absoluteString;
    // 可自定义匹配规则
    return [url containsString:@"/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - NSURLSession Hook
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        [[FloatingLogView sharedInstance] log:@"🎯 拦截 URL: %@", request.URL.absoluteString];

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *resp, NSError *err) {

            if (err) {
                [[FloatingLogView sharedInstance] log:@"⚠️ 原始请求出错: %@", err];
                if (completionHandler) completionHandler(data, resp, err);
                return;
            }

            // 构造伪造 JSON
            NSString *jsonStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"data\":{}}";
            NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];

            NSHTTPURLResponse *newResp = [[NSHTTPURLResponse alloc]
                initWithURL:request.URL
                statusCode:200
                HTTPVersion:@"HTTP/1.1"
                headerFields:@{@"Content-Type":@"application/json"}];

            [[FloatingLogView sharedInstance] log:@"🔓 返回伪造数据: %@", jsonStr];

            completionHandler(fakeData, newResp, nil);
        };

        return %orig(request, newHandler);
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - CFNetwork / NSURLConnection Hook
%hook NSURLConnection

+ (instancetype)sendSynchronousRequest:(NSURLRequest *)request
                      returningResponse:(NSURLResponse **)response
                                  error:(NSError **)error {
    if (isTarget(request)) {
        [[FloatingLogView sharedInstance] log:@"🎯 拦截 NSURLConnection URL: %@", request.URL.absoluteString];
        NSString *jsonStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"data\":{}}";
        NSData *fakeData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];

        if (response) {
            *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                      statusCode:200
                                                     HTTPVersion:@"HTTP/1.1"
                                                    headerFields:@{@"Content-Type":@"application/json"}];
        }
        return fakeData;
    }
    return %orig(request, response, error);
}

%end

#pragma mark - 启动 UI
%ctor {
    [FloatingLogView sharedInstance];
}