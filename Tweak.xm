#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 创建日志窗口

@interface LogWindow : UIViewController

@property (nonatomic, strong) UITextView *logTextView;

+ (instancetype)sharedInstance;
- (void)appendLog:(NSString *)log;

@end

@implementation LogWindow

+ (instancetype)sharedInstance {
    static LogWindow *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[LogWindow alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初始化UI组件
        self.view.backgroundColor = [UIColor whiteColor];
        
        // 创建日志显示区域
        self.logTextView = [[UITextView alloc] initWithFrame:self.view.bounds];
        self.logTextView.editable = NO;
        self.logTextView.font = [UIFont systemFontOfSize:14];
        self.logTextView.textColor = [UIColor blackColor];
        self.logTextView.backgroundColor = [UIColor lightGrayColor];
        [self.view addSubview:self.logTextView];
    }
    return self;
}

- (void)appendLog:(NSString *)log {
    // 确保UI更新在主线程
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = self.logTextView.text;
        self.logTextView.text = [currentText stringByAppendingFormat:@"%@\n", log];
        
        // 滚动到最新日志
        NSRange range = NSMakeRange(self.logTextView.text.length, 0);
        [self.logTextView scrollRangeToVisible:range];
    });
}

@end

#pragma mark - 构造 JSON
NSData *buildJSON() {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(ts)
    };

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    NSLog(@"[Hook] 检查 URL: %@", urlString);  // 打印请求 URL，用于调试

    // 使用更精确的匹配方式，确保只匹配特定请求
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSString *logMessage = [NSString stringWithFormat:@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString];
        [[LogWindow sharedInstance] appendLog:logMessage];  // 输出日志到 UI

        // 防递归
        if ([request valueForHTTPHeaderField:@"X-Hooked"]) {
            logMessage = [NSString stringWithFormat:@"[Hook] 跳过递归请求: %@", request.URL.absoluteString];
            [[LogWindow sharedInstance] appendLog:logMessage];
            return %orig(request, completionHandler);
        }

        // 拷贝请求以修改它
        NSMutableURLRequest *req = [request mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:@"X-Hooked"];  // 防止递归

        // 创建新的处理回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            // 错误处理
            if (error) {
                NSString *errorMessage = [NSString stringWithFormat:@"[Hook] 请求失败: %@", error.localizedDescription];
                [[LogWindow sharedInstance] appendLog:errorMessage];
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // 打印原始数据
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSString *logMessage = [NSString stringWithFormat:@"[Hook] 原始返回: %@", str];
                [[LogWindow sharedInstance] appendLog:logMessage];
            }

            // 替换数据
            NSData *newData = buildJSON();
            
            // 确保数据有效，并且 UI 更新操作在主线程
            NSString *newLogMessage = [NSString stringWithFormat:@"[Hook] 修改后的返回: %@", [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]];
            [[LogWindow sharedInstance] appendLog:newLogMessage];

            // 返回修改后的数据
            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        // 执行原始请求，并传递新的回调
        return %orig(req, newHandler);
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - 在应用中显示日志窗口
// 在某个地方（比如 AppDelegate 或 ViewController）展示 LogWindow
LogWindow *logWindow = [LogWindow sharedInstance];
[self.window.rootViewController presentViewController:logWindow animated:YES completion:nil];