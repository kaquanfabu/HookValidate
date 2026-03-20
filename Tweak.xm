#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>
#import <objc/runtime.h>

#pragma mark - UI Logger

@interface HookLogger : NSObject
+ (void)initUI;
+ (void)log:(NSString *)fmt, ...;
@end

@implementation HookLogger

static UITextView *textView;
static UIView *panel;
static BOOL hidden = NO;

+ (UIWindow *)getKeyWindow {

    UIWindow *win = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {

                UIWindowScene *ws = (UIWindowScene *)scene;

                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) {
                        win = w;
                        break;
                    }
                }
            }
            if (win) break;
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        win = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }

    return win;
}

+ (void)initUI {
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *win = [self getKeyWindow];
        if (!win) return;

        panel = [[UIView alloc] initWithFrame:CGRectMake(20, 120, 320, 260)];
        panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        panel.layer.cornerRadius = 10;
        panel.clipsToBounds = YES;

        textView = [[UITextView alloc] initWithFrame:panel.bounds];
        textView.backgroundColor = [UIColor clearColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont systemFontOfSize:10];
        textView.editable = NO;

        [panel addSubview:textView];

        // ✅ 拖动手势
        UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [panel addGestureRecognizer:pan];

        // ✅ 双击隐藏
        UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        tap.numberOfTapsRequired = 2;
        [panel addGestureRecognizer:tap];

        [win addSubview:panel];
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

+ (void)log:(NSString *)fmt, ... {

    va_list args;
    va_start(args, fmt);
    NSString *str = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSLog(@"%@", str);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!textView) return;

        NSString *newText = [textView.text stringByAppendingFormat:@"\n%@", str];
        textView.text = newText;

        // 自动滚动
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

#pragma mark - Alamofire Hook（核心）

%hook Alamofire_DataTaskDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSString *url = dataTask.originalRequest.URL.absoluteString;

    if (url) {
        [HookLogger log:@"🌐 %@", url];
    }

    if ([url containsString:@"validate"]) {

        [HookLogger log:@"🔥 HIT %@", url];

        NSData *newData = buildFakeData();

        if ([dataTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
            if (isGzip((NSHTTPURLResponse *)dataTask.response)) {
                NSData *gz = gzipCompress(newData);
                if (gz) newData = gz;
            }
        }

        %orig(session, dataTask, newData);
        return;
    }

    %orig(session, dataTask, data);
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
        [HookLogger log:@"✅ UI Ready"];
    });
}
