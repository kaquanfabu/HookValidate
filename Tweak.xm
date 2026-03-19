#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 解压
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

        if (status == Z_STREAM_END) {
            done = YES;
        } else if (status != Z_OK) {
            break;
        }
    }

    if (inflateEnd(&strm) != Z_OK) return nil;

    if (done) {
        decompressed.length = strm.total_out;
        return decompressed;
    }

    return nil;
}

#pragma mark - gzip 压缩
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

#pragma mark - 判断 gzip
BOOL isGzip(NSHTTPURLResponse *resp) {
    NSString *encoding = resp.allHeaderFields[@"Content-Encoding"];
    if (!encoding) return NO;
    return [encoding.lowercaseString containsString:@"gzip"];
}

#pragma mark - 生成假数据
NSData *buildFakeData(void) {
    NSDictionary *fake = @{
        @"code": @0,
        @"message": @"hook success",
        @"data": [NSNull null],
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };

    return [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
}

#pragma mark - 自定义日志窗口

// 创建一个自定义 UIView，用来显示日志内容
@interface LogWindow : UIWindow
@property (nonatomic, strong) UITextView *textView;
@end

@implementation LogWindow

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(100, 100, 300, 300)];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
        self.layer.cornerRadius = 10.0;
        
        // 创建一个 TextView 来显示日志
        self.textView = [[UITextView alloc] initWithFrame:self.bounds];
        self.textView.font = [UIFont systemFontOfSize:14];
        self.textView.textColor = [UIColor whiteColor];
        self.textView.backgroundColor = [UIColor clearColor];
        self.textView.editable = NO;
        self.textView.scrollEnabled = YES;
        [self addSubview:self.textView];
        
        // 允许拖动
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
        [self addGestureRecognizer:panGesture];
    }
    return self;
}

// 处理拖动事件
- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    CGPoint translation = [gestureRecognizer translationInView:self];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gestureRecognizer setTranslation:CGPointZero inView:self];
}

- (void)addLog:(NSString *)log {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = [self.textView.text stringByAppendingFormat:@"%@\n", log];
        // 保持滚动条在底部
        NSRange range = NSMakeRange(self.textView.text.length, 0);
        [self.textView scrollRangeToVisible:range];
    });
}

@end

#pragma mark - 初始化 LogWindow
static LogWindow *logWindow = nil;

void initLogWindow() {
    if (!logWindow) {
        logWindow = [[LogWindow alloc] init];
        [logWindow makeKeyAndVisible];
    }
}

void addLogToWindow(NSString *log) {
    if (logWindow) {
        [logWindow addLog:log];
    }
}

#pragma mark - NSURLSession Hook

// 重写 URLSession 的方法进行自定义逻辑处理
@implementation MySessionDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    NSLog(@"[Hook-Delegate] %@", dataTask.originalRequest.URL.absoluteString);
    addLogToWindow([NSString stringWithFormat:@"[Delegate] %@", dataTask.originalRequest.URL.absoluteString]);

    NSData *newData = data;

    if ([dataTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)dataTask.response;

        // 解 gzip
        if (isGzip(resp)) {
            NSData *de = gzipDecompress(data);
            if (de) newData = de;
        }

        // 替换
        newData = buildFakeData();

        // 压回 gzip
        if (isGzip(resp)) {
            NSData *re = gzipCompress(newData);
            if (re) newData = re;
        }
    }

    // 将修改后的数据传递给任务
    [dataTask setResponseData:newData];
}

@end
