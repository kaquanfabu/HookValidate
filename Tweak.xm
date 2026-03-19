#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 工具

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;

    unsigned full_length = (unsigned)data.length;
    unsigned half_length = (unsigned)data.length / 2;

    NSMutableData *decompressed = [NSMutableData dataWithLength:full_length + half_length];

    z_stream strm;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;

    if (inflateInit2(&strm, (15+32)) != Z_OK) return nil;

    BOOL done = NO;
    while (!done) {
        if (strm.total_out >= decompressed.length)
            decompressed.length += half_length;

        strm.next_out = decompressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(decompressed.length - strm.total_out);

        int status = inflate(&strm, Z_SYNC_FLUSH);

        if (status == Z_STREAM_END) done = YES;
        else if (status != Z_OK) break;
    }

    inflateEnd(&strm);

    if (done) {
        decompressed.length = strm.total_out;
        return decompressed;
    }

    return nil;
}

NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    do {
        if (strm.total_out >= compressed.length)
            compressed.length += 16384;

        strm.next_out = compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);

        deflate(&strm, Z_FINISH);

    } while (strm.avail_out == 0);

    deflateEnd(&strm);

    compressed.length = strm.total_out;
    return compressed;
}

BOOL isGzip(NSHTTPURLResponse *resp) {
    NSString *encoding = resp.allHeaderFields[@"Content-Encoding"];
    return encoding && [encoding.lowercaseString containsString:@"gzip"];
}

#pragma mark - 伪造数据

NSData *buildFakeData(void) {
    NSDictionary *fake = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970]*1000))
    };
    return [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
}

#pragma mark - 日志窗口

@interface LogWindow : UIWindow
@property(nonatomic,strong) UITextView *textView;
@end

@implementation LogWindow

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(50,100,300,300)];
    self.windowLevel = UIWindowLevelAlert + 1;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];

    self.textView = [[UITextView alloc] initWithFrame:self.bounds];
    self.textView.backgroundColor = UIColor.clearColor;
    self.textView.textColor = UIColor.greenColor;
    self.textView.editable = NO;

    [self addSubview:self.textView];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(move:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)move:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];
}

- (void)add:(NSString *)log {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = [self.textView.text stringByAppendingFormat:@"%@\n", log];
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
    });
}

@end

static LogWindow *win;

void logx(NSString *s) {
    if (!win) {
        win = [LogWindow new];
        [win makeKeyAndVisible];
    }
    [win add:s];
}

#pragma mark - SSL 绕过

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    %orig(session, challenge, completionHandler);
}

%end

#pragma mark - 核心拦截（Alamofire 关键）

%hook%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    NSString *url = request.URL.absoluteString;

    return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {

        if (!data || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
            completionHandler(data, response, error);
            return;
        }

        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;

        if ([url containsString:@"/menu/validate"]) {

            NSData *newData = data;

            // 解 gzip
            NSString *encoding = resp.allHeaderFields[@"Content-Encoding"];
            if (encoding && [encoding.lowercaseString containsString:@"gzip"]) {
                NSData *de = gzipDecompress(data);
                if (de) newData = de;
            }

            // 替换数据
            newData = buildFakeData();

            // 压回 gzip
            if (encoding && [encoding.lowercaseString containsString:@"gzip"]) {
                NSData *re = gzipCompress(newData);
                if (re) newData = re;
            }

            completionHandler(newData, response, nil);
            return;
        }

        completionHandler(data, response, error);
    });
}

%end

#pragma mark - 初始化

%ctor {
    NSLog(@"[Tweak] Loaded");
}