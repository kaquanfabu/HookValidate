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
        logger.windowLevel = UIWindowLevelAlert + 1;
        logger.hidden = NO;

        logger.textView = [[UITextView alloc] initWithFrame:logger.bounds];
        logger.textView.backgroundColor = [UIColor clearColor];
        logger.textView.textColor = [UIColor greenColor];
        logger.textView.editable = NO;
        logger.textView.font = [UIFont systemFontOfSize:12];
        [logger addSubview:logger.textView];
    });
    return logger;
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

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

#pragma mark - NSURLSession Delegate (AFNetworking / Alamofire)

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

#pragma mark - NSURLConnection Hook

%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    if (isTarget(request)) return YES;
    return %orig;
}

- (void)start {
    if (isTarget(self.currentRequest)) {
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

        [self setValue:newData forKey:@"_data"];
        [self setValue:newResp forKey:@"_response"];

        [[HookLoggerView sharedLogger] log:@"[NSURLConnection] URL: %@\nResponse: %@", self.currentRequest.URL.absoluteString, [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]];
    }
    %orig;
}

%end