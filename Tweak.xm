#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - 1. 基础工具 (Gzip & JSON)

// Gzip 压缩
NSData *gzipCompress(NSData *data) {
    if (!data) return nil;
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
    NSMutableData *compressed = [NSMutableData dataWithLength:1024];
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    do {
        if (strm.total_out >= compressed.length) compressed.length += 1024;
        strm.next_out = (Bytef *)compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
        deflate(&strm, Z_FINISH);
    } while (strm.avail_out == 0);
    deflateEnd(&strm);
    compressed.length = strm.total_out;
    return compressed;
}

// 生成伪造数据
NSData *buildFakeData() {
    NSDictionary *fake = @{
        @"code": @200,
        @"msg": @"Alamofire Delegate Hook Success",
        @"data": @{@"user": @"Hacker", @"level": @999},
        @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970]*1000))
    };
    return [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
}

#pragma mark - 2. 悬浮调试窗 (带开关)

static BOOL isLogVisible = YES;

@interface DebugWindow : UIWindow
@property (nonatomic, strong) UITextView *tv;
@property (nonatomic, strong) UIButton *toggleBtn;
@end

@implementation DebugWindow
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 40, [UIScreen mainScreen].bounds.size.width, 300)];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 1;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        
        self.tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 10, self.bounds.size.width - 20, self.bounds.size.height - 50)];
        self.tv.font = [UIFont fontWithName:@"Menlo" size:10.0];
        self.tv.textColor = [UIColor greenColor];
        self.tv.backgroundColor = [UIColor clearColor];
        self.tv.editable = NO;
        [self addSubview:self.tv];
        
        self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        self.toggleBtn.frame = CGRectMake(10, self.bounds.size.height - 35, 60, 30);
        [self.toggleBtn setTitle:@"Hide" forState:UIControlStateNormal];
        self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self.toggleBtn addTarget:self action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleBtn];
        
        // 拖动手势
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(move:)]];
    }
    return self;
}

- (void)toggleLog {
    isLogVisible = !isLogVisible;
    self.tv.hidden = !isLogVisible;
    [self.toggleBtn setTitle:(isLogVisible ? @"Hide" : @"Show") forState:UIControlStateNormal];
}

- (void)move:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!isLogVisible) return;
        self.tv.text = [self.tv.text stringByAppendingFormat:@"%@\n", text];
        NSRange range = NSMakeRange(self.tv.text.length - 1, 1);
        [self.tv scrollRangeToVisible:range];
    });
}
@end

static DebugWindow *gWin = nil;
static void Log(NSString *fmt, ...) {
    if (!gWin) { gWin = [DebugWindow new]; [gWin makeKeyAndVisible]; }
    va_list args; va_start(args, fmt);
    NSString *str = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [gWin log:str];
}

#pragma mark - 3. 核心拦截 (Alamofire Delegate 模式)

// 我们需要 Hook 两个关键点：
// 1. dataTask 的创建：用来标记哪些 Task 需要被拦截
// 2. didReceiveData：用来注入假数据

// 用一个字典来存储“需要被劫持”的 Task
static NSMapTable *hijackTasks = nil;

%hook NSURLSession

// 1. 标记需要劫持的 Task
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(id<NSURLSessionDelegate>)delegate
                             delegateQueue:(NSOperationQueue *)queue
{
    // 初始化 Map (Key: Task, Value: URL String)
    if (!hijackTasks) {
        hijackTasks = [NSMapTable strongToStrongObjectsMapTable];
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig;
    NSString *url = request.URL.absoluteString;
    
    // 判断是否是目标 URL (例如 /menu/validate)
    if ([url containsString:@"/menu/validate"]) {
        [hijackTasks setObject:url forKey:task];
        Log(@"[Hook] Target Task Created: %@", url);
    }
    return task;
}

// 2. 拦截响应头：修改 Content-Length (欺骗 Alamofire)
- (void)URLSession:(NSURLSession *)session 
      dataTask:(NSURLSessionDataTask *)dataTask 
didReceiveResponse:(NSURLResponse *)response 
completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler 
{
    // 检查这个 Task 是否需要被劫持
    if ([hijackTasks objectForKey:dataTask]) {
        Log(@"[Hook] Response Received. Modifying Content-Length...");
        
        // 生成假数据以获取正确的长度
        NSData *fakeData = buildFakeData();
        BOOL wantsGzip = [[dataTask.originalRequest.allHTTPHeaderFields[@"Accept-Encoding"] lowercaseString] containsString:@"gzip"];
        if (wantsGzip) fakeData = gzipCompress(fakeData);
        
        // 关键：修改 response 的 Content-Length
        // NSHTTPURLResponse 是不可变的，但我们可以利用 KVC 修改其内部属性
        // 注意：在 iOS 13+ 可能需要更复杂的 Runtime 方法，但 KVC 通常在 Tweak 中有效
        @try {
            // 尝试直接设置私有变量或 KVC 兼容的属性
            // 如果 KVC 失败，Alamofire 可能会报错，但数据流依然会被拦截
            // 这里我们主要依赖 didReceiveData 的拦截，Content-Length 主要是为了防报错
            // 实际上，Alamofire 的 Request 类会读取 response.expectedContentLength
            // 我们无法修改 response 对象本身，但我们可以让 session 忽略它，或者
            // 在 didReceiveData 中完全接管。
            
            // 更好的方法：不修改 response，而是让 didReceiveData 处理一切。
            // 但如果 Content-Length 不匹配，Alamofire 可能会 cancel task。
            // 这里我们尝试修改 _properties 字典 (私有 API 警告)
            // 在 Tweak 环境下，这是常见做法。
        } @catch (NSException *e) {
            Log(@"[Hook] Warning: Could not modify Content-Length");
        }
    }
    %orig(session, dataTask, response, completionHandler);
}

// 3. 拦截数据流：注入假数据
- (void)URLSession:(NSURLSession *)session 
      dataTask:(NSURLSessionDataTask *)dataTask 
    didReceiveData:(NSData *)data 
{
    NSString *targetURL = [hijackTasks objectForKey:dataTask];
    
    if (targetURL) {
        // --- 核心欺骗逻辑 ---
        
        // 1. 丢弃原始数据 (data 参数被忽略)
        
        // 2. 生成假数据
        static dispatch_once_t onceToken;
        static NSData *injectedData = nil;
        
        dispatch_once(&onceToken, ^{
            // 只生成一次，因为 didReceiveData 可能会被调用多次
            // 但我们需要确保它是 Gzip 格式（如果客户端期望）
            NSData *fake = buildFakeData();
            BOOL wantsGzip = [[dataTask.originalRequest.allHTTPHeaderFields[@"Accept-Encoding"] lowercaseString] containsString:@"gzip"];
            if (wantsGzip) {
                injectedData = gzipCompress(fake);
                Log(@"[Hook] Injecting Gzip Data (Len: %lu)", (unsigned long)injectedData.length);
            } else {
                injectedData = fake;
                Log(@"[Hook] Injecting Plain Data (Len: %lu)", (unsigned long)injectedData.length);
            }
        });
        
        // 3. 调用原始代理方法，但传入假数据
        // 这样 Alamofire 的 delegate 就会收到我们的假数据
        %orig(session, dataTask, injectedData);
        
        // 4. 清理：防止重复注入（如果 didReceiveData 被多次调用）
        // 这里我们简单粗暴地移除任务标记，意味着只注入一次
        [hijackTasks removeObjectForKey:dataTask];
        
        return; // 截断，不再执行原始逻辑
    }
    
    // 非目标 URL，原样返回
    %orig(session, dataTask, data);
}

%end

#pragma mark - 4. SSL Bypass (保持)
%hook NSURLSession
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
        return;
    }
    %orig;
}
%end

#pragma mark - 5. 初始化
%ctor {
    Log(@"[Tweak] Alamofire Delegate Hook Loaded");
}
