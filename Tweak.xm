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

            NSString *fake = @"{ \
            \"sing\":null,\
            \"data\":null,\
            \"code\":0,\
            \"message\":\"请求成功\",\
            \"success\":true,\
            \"skey\":null,\
            \"timestamp\":1773846248358\
            }";

            NSData *newData = [fake dataUsingEncoding:NSUTF8StringEncoding];

            completionHandler(newData,response,error);
        };

        return %orig(request,newHandler);
    }

    return %orig(request,completionHandler);
}

%end
