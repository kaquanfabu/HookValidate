#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - UI 日志窗口

@interface HookLoggerView : UIWindow
@property (nonatomic, strong) UITextView *textView;
+ (instancetype)sharedLogger;
- (void)log:(NSString *)fmt, ...;
@end

@implementation HookLoggerView

+ (instancetype)sharedLogger {
    static HookLoggerView *logger;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect frame = CGRectMake(0, 100, [UIScreen mainScreen].bounds.size.width, 200);
        logger = [[HookLoggerView alloc] initWithFrame:frame];
        logger.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        logger.windowLevel = UIWindowLevelAlert + 2;  // 设置更高的 windowLevel，确保窗口在最上层
        logger.hidden = NO;  // 确保窗口不隐藏

        // 创建日志显示区域
        logger.textView = [[UITextView alloc] initWithFrame:logger.bounds];
        logger.textView.backgroundColor = [UIColor clearColor];
        logger.textView.textColor = [UIColor greenColor];
        logger.textView.editable = NO;
        logger.textView.font = [UIFont systemFontOfSize:12];
        [logger addSubview:logger.textView];

        // 显式调用 makeKeyAndVisible 确保窗口可见
        [logger makeKeyAndVisible];
    });
    return logger;
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // 更新 UI 必须在主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = [self.textView.text stringByAppendingFormat:@"\n%@", msg];
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 1)];
    });
}

@end

#pragma mark - 目标 URL 判断

BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 构造伪造数据

NSData *buildFakeData() {
    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSDictionary *fake = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(timestamp)
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];

    [[HookLoggerView sharedLogger] log:@"[FakeData] %@", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]];
    return jsonData;
}

#pragma mark - NSURLSession Hook (completionHandler)

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSData *newData = buildFakeData();

            NSHTTPURLResponse *oldResp = (NSHTTPURLResponse *)response;
            NSDictionary *headers = @{
                @"Content-Type": @"application/json;charset=UTF-8",
                @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)newData.length]
            };

            NSHTTPURLResponse *newResp =
            [[NSHTTPURLResponse alloc] initWithURL:oldResp.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:headers];

            [[HookLoggerView sharedLogger] log:@"[NSURLSession] URL: %@\nResponse: %@", request.URL.absoluteString, [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]];

            completionHandler(newData, newResp, nil);
        };

        return %orig(request, newHandler);
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - NSURLSessionTask Delegate (AFNetworking / Alamofire)

%hook NSURLSessionTask

- (void)setState:(NSURLSessionTaskState)state {
    %orig;

    if (state == NSURLSessionTaskStateCompleted) {
        NSURLRequest *req = self.currentRequest;
        if (!isTarget(req)) return;

        NSData *newData = buildFakeData();

        NSHTTPURLResponse *oldResp = (NSHTTPURLResponse *)self.response;
        NSDictionary *headers = @{
            @"Content-Type": @"application/json;charset=UTF-8",
            @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)newData.length]
        };

        NSHTTPURLResponse *newResp =
        [[NSHTTPURLResponse alloc] initWithURL:oldResp.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];

        [self setValue:newData forKey:@"_responseData"];
        [self setValue:newResp forKey:@"_response"];

        [[HookLoggerView sharedLogger] log:@"[DelegateHook] URL: %@\nResponse: %@", req.URL.absoluteString, [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]];
    }
}

%end

#pragma mark - NSURLConnection Hook (delegate)

%hook NSObject

// 拦截 delegate 回调：接收 response
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (isTarget(connection.currentRequest)) {
        NSHTTPURLResponse *newResp = [[NSHTTPURLResponse alloc] initWithURL:response.URL
                                                                  statusCode:200
                                                                 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Content-Type": @"application/json;charset=UTF-8"}];
        [self setValue:newResp forKey:@"_response"];
        [[HookLoggerView sharedLogger] log:@"[NSURLConnection] URL: %@, hooked response", connection.currentRequest.URL.absoluteString];
    }
    %orig(connection, response);
}

// 拦截 delegate 回调：接收 data
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (isTarget(connection.currentRequest)) {
        NSData *newData = buildFakeData();
        [self setValue:newData forKey:@"_data"];
        [[HookLoggerView sharedLogger] log:@"[NSURLConnection] URL: %@, hooked data", connection.currentRequest.URL.absoluteString];
        return; // 拦截原始数据
    }
    %orig(connection, data);
}

// 完成回调
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (isTarget(connection.currentRequest)) {
        [[HookLoggerView sharedLogger] log:@"[NSURLConnection] URL: %@, finished loading", connection.currentRequest.URL.absoluteString];
    }
    %orig(connection);
}

%end

#pragma mark - NSURLConnection canHandleRequest

%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    if (isTarget(request)) return YES;
    return %orig;
}

%end