#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// 定义关联对象 Key
static char kOriginalDelegateKey;

// 1. 判断是否为目标请求
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}


// 2. Gzip 压缩工具
static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15 + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];
    do {
        if (strm.total_out >= compressed.length) {
            [compressed increaseLengthBy:16384];
        }
        strm.next_out = ((Bytef *)compressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
    } while (deflate(&strm, Z_FINISH) == Z_OK);

    deflateEnd(&strm);
    [compressed setLength:strm.total_out];
    return compressed;
}

// 3. 构造伪造数据 (保持简单，只改 code 和 message)
static NSData *fakeJsonData() {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSDictionary *obj = @{
        @"code": @0,
        @"message": @"请求成功 (Hooked)",
        @"success": @YES,
        @"data": [NSNull null] // 确保 data 字段存在，避免 App 崩溃
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
    if (error) {
        NSLog(@"[Error] JSON 序列化失败: %@", error);
        return nil;
    }

    return gzipData(jsonData);
}

// 4. 自定义代理类 (同上)
@interface MyCustomDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) id<NSURLSessionDataDelegate> originalDelegate;
- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate;
@end

@implementation MyCustomDelegate
- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate {
    self = [super init];
    if (self) {
        _originalDelegate = delegate;
    }
    return self;
}

// 拦截 didReceiveData
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // 检查是否是目标请求
    if (isTargetRequest(dataTask.originalRequest)) {
        NSLog(@"[Hook] ✅ 拦截到数据传输: %@", dataTask.originalRequest.URL);

        // 发送伪造数据
        NSData *fakeData = fakeJsonData();
        if (fakeData) {
            // 调用原始代理的 didReceiveData，传递伪造的数据
            if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
                [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:fakeData];
            }
        }
    } else {
        // 非目标请求，调用原始逻辑
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:data];
        }
    }
}

// 拦截任务完成
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        // 传递 nil 错误，表示任务成功完成
        [self.originalDelegate URLSession:session task:task didCompleteWithError:nil];
    }
}
@end

// 5. Hook Session 的初始化 (关键点!)
%hook NSURLSession

// Hook 无参数初始化
- (instancetype)init {
    id session = %orig;
    // 保存原始 Delegate 并替换
    id originalDelegate = [session delegate];
    if (originalDelegate) {
        MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:originalDelegate];
        [session setDelegate:customDelegate];
    }
    return session;
}

// Hook 带配置的初始化 (更常见)
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    id session = %orig(configuration, delegate, queue);
    if (delegate) {
        MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:delegate];
        return %new(session, configuration, customDelegate, queue); // 这里需要根据实际情况调整，或者直接在内部替换
    }
    return session;
}
%end

// 6. Hook Task 的初始化 (双重保险)
%hook NSURLSessionTask

- (void)setDelegate:(id<NSURLSessionTaskDelegate>)delegate {
    // 保存原始 Delegate
    objc_setAssociatedObject(self, &kOriginalDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN);
    // 替换为自定义 Delegate
    MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:delegate];
    %orig(customDelegate);
}

- (id<NSURLSessionTaskDelegate>)delegate {
    id<NSURLSessionTaskDelegate> del = %orig;
    return del;
}
%end
