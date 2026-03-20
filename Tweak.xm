#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - 全局

static UIView *panel;

#pragma mark - 穿透 Window

@interface PassThroughWindow : UIWindow
@end

@implementation PassThroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {

    UIView *view = [super hitTest:point withEvent:event];

    if (view && panel && [view isDescendantOfView:panel]) {
        return view;
    }

    return nil;
}

@end

#pragma mark - UI Logger

@interface HookLogger : NSObject
+ (void)initUI;
+ (void)log:(NSString *)fmt, ...;
+ (void)keepAlive;
@end

@implementation HookLogger

static UITextView *textView;
static UIWindow *overlayWindow;
static BOOL hidden = NO;

+ (void)initUI {

    dispatch_async(dispatch_get_main_queue(), ^{

        if (overlayWindow) return;

        CGRect frame = [UIScreen mainScreen].bounds;

        overlayWindow = [[PassThroughWindow alloc] initWithFrame:frame];
        overlayWindow.windowLevel = UIWindowLevelAlert + 100;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.hidden = NO;
        overlayWindow.userInteractionEnabled = YES;

        UIViewController *vc = [UIViewController new];
        overlayWindow.rootViewController = vc;

        panel = [[UIView alloc] initWithFrame:CGRectMake(20, 120, 320, 260)];
        panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        panel.layer.cornerRadius = 10;

        textView = [[UITextView alloc] initWithFrame:panel.bounds];
        textView.backgroundColor = [UIColor clearColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont systemFontOfSize:10];
        textView.editable = NO;

        [panel addSubview:textView];

        UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [panel addGestureRecognizer:pan];

        UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        tap.numberOfTapsRequired = 2;
        [panel addGestureRecognizer:tap];

        // 三指切换（防隐藏后点不到）
        UITapGestureRecognizer *triple =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        triple.numberOfTouchesRequired = 3;
        [overlayWindow addGestureRecognizer:triple];

        [overlayWindow addSubview:panel];
    });
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:panel.superview];
    panel.center = CGPointMake(panel.center.x + t.x, panel.center.y + t.y);
    [pan setTranslation:CGPointZero inView:panel.superview];
}

+ (void)toggle {
    hidden = !hidden;
    panel.alpha = hidden ? 0.1 : 1.0;
}

+ (void)keepAlive {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (overlayWindow) overlayWindow.hidden = NO;
        [self keepAlive];
    });
}

+ (void)log:(NSString *)fmt, ... {

    va_list args;
    va_start(args, fmt);
    NSString *str = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSLog(@"%@", str);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!textView) return;

        textView.text = [textView.text stringByAppendingFormat:@"\n%@", str];

        NSRange range = NSMakeRange(textView.text.length - 1, 1);
        [textView scrollRangeToVisible:range];
    });
}

@end

#pragma mark - gzip

NSData *gzipDecompress(NSData *data) {
    if (!data.length) return data;

    NSMutableData *out = [NSMutableData dataWithLength:data.length * 2];
    z_stream strm = {0};

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    if (inflateInit2(&strm, 15+32) != Z_OK) return nil;

    while (1) {
        if (strm.total_out >= out.length)
            out.length += data.length;

        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);

        int status = inflate(&strm, Z_SYNC_FLUSH);

        if (status == Z_STREAM_END) break;
        if (status != Z_OK) {
            inflateEnd(&strm);
            return nil;
        }
    }

    inflateEnd(&strm);
    out.length = strm.total_out;
    return out;
}

NSData *gzipCompress(NSData *data) {
    if (!data.length) return data;

    NSMutableData *out = [NSMutableData dataWithLength:16384];
    z_stream strm = {0};

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     15+16, 8, Z_DEFAULT_STRATEGY) != Z_OK)
        return nil;

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    do {
        if (strm.total_out >= out.length)
            out.length += 16384;

        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);

        deflate(&strm, Z_FINISH);

    } while (strm.avail_out == 0);

    deflateEnd(&strm);
    out.length = strm.total_out;
    return out;
}

BOOL isGzip(NSHTTPURLResponse *resp) {
    NSString *e = resp.allHeaderFields[@"Content-Encoding"];
    return e && [e.lowercaseString containsString:@"gzip"];
}

#pragma mark - Fake Data

NSData *buildFakeData(void) {
    NSDictionary *json = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970]*1000))
    };
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
}

#pragma mark - ⭐ 主拦截（100%命中）

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    NSURL *u = request.URL;
    NSString *host = u.host;
    NSString *path = u.path;
    NSString *urlStr = u.absoluteString;

    // 🔥 包一层 block（关键）
    void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {

        if (urlStr) {
            [HookLogger log:@"🌐 %@", urlStr];
        }

        if ([host isEqualToString:@"wap.jx.10086.cn"] &&
            [path containsString:@"/menu/validate"])
        {
            [HookLogger log:@"🔥 HIT validate"];

            NSData *newData = buildFakeData();

            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                if (isGzip((NSHTTPURLResponse *)response)) {
                    NSData *gz = gzipCompress(newData);
                    if (gz) newData = gz;
                }
            }

            completionHandler(newData, response, error);
            return;
        }

        completionHandler(data, response, error);
    };

    // ✅ 再调用 orig（不会报错）
    return %orig(request, newHandler);
}

%end
#pragma mark - 兜底日志

%hook NSURLSessionDataTask

- (void)resume {
    NSString *url = self.originalRequest.URL.absoluteString;
    if (url) {
        [HookLogger log:@"📡 TASK %@", url];
    }
    %orig;
}

%end

#pragma mark - SSL 绕过

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    NSURLCredential *cred =
    [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];

    completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
}

%end

#pragma mark - ctor

%ctor {
    NSLog(@"🚀 Hook Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [HookLogger initUI];
        [HookLogger keepAlive];
        [HookLogger log:@"✅ UI Ready"];
    });
}
