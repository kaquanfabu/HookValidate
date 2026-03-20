#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>
#import <objc/runtime.h>

#pragma mark - UI 日志面板

@interface HookLogger : NSObject
+ (void)log:(NSString *)fmt, ...;
@end

@implementation HookLogger

static UITextView *textView;

+ (void)initUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;

        UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(10, 100, 350, 300)];
        panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        panel.layer.cornerRadius = 10;

        textView = [[UITextView alloc] initWithFrame:panel.bounds];
        textView.backgroundColor = [UIColor clearColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont systemFontOfSize:10];
        textView.editable = NO;

        [panel addSubview:textView];
        [win addSubview:panel];
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

        strm.next_out = out.mutableBytes + strm.total_out;
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

        strm.next_out = out.mutableBytes + strm.total_out;
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

#pragma mark - Fake 数据

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

#pragma mark - Hook Alamofire DataTaskDelegate（核心）

%hook Alamofire_DataTaskDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSString *url = dataTask.originalRequest.URL.absoluteString;

    if ([url containsString:@"validate"]) {

        [HookLogger log:@"🔥 HIT Alamofire: %@", url];

        NSData *newData = buildFakeData();

        if ([dataTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *resp = (NSHTTPURLResponse *)dataTask.response;

            if (isGzip(resp)) {
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

#pragma mark - 兜底 NSURLSession（防漏）

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
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
