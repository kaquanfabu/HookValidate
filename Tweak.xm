#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// 定义关联对象 Key，用于保存原始 Delegate
static char kOriginalDelegateKey;

// ================= 配置区域 =================
// 在这里配置你要拦截的 URL 关键字
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // 只要包含这个字符串就会被拦截，建议写长一点避免误伤
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}
// =============================================

// 1. Gzip 压缩工具
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

// 2. 构造伪造数据
static NSData *fakeJsonData() {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSDictionary *obj = @{
        @"code": @0,
        @"message": @"Hook Success",
        @"success": @YES,
        @"data": @{} // 返回空字典，防止 App 崩溃
    };
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
    if (error) return nil;

    return gzipData(jsonData);
}

// 3. 自定义 Delegate 类
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

// 拦截数据接收
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // 检查是否为目标请求
    if (isTargetRequest(dataTask.originalRequest)) {
        NSLog(@"[Hook] 🎯 拦截到数据: %@", dataTask.originalRequest.URL);
        
        // 获取伪造数据
        NSData *fakeData = fakeJsonData();
        if (fakeData && [self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            // 把伪造数据传给原始 Delegate
            [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:fakeData];
            return; // 拦截成功，不再处理
        }
    }
    
    // 非目标请求，或者伪造失败，走原始逻辑
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

// 拦截任务完成
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // 如果是目标请求，强制认为成功（error = nil）
    if (isTargetRequest(task.originalRequest)) {
         if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:nil];
        }
        return;
    }
    
    // 非目标请求，走原始逻辑
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

@end

// ================= Hook 区域 =================

// 4. Hook NSURLSession 的初始化
// 这样能确保 App 创建 Session 时，我们就知道它的 Delegate 是谁
%hook NSURLSession

// Hook 最常用的初始化方法
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    // 先调用原始初始化
    NSURLSession *session = %orig;
    
    // 如果这个 Session 有 Delegate，我们尝试 Hook 它创建的任务
    // 注意：这里不需要替换 Session 的 Delegate，因为我们要 Hook 的是 Task 的 Delegate
    return session;
}

%end

// 5. Hook DataTask 的创建
// 这是最关键的一步，在 Task 被创建出来时，我们强制替换它的 Delegate
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    // 1. 先创建原始 Task
    NSURLSessionDataTask *task = %orig;
    
    // 2. 判断是否是目标请求
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🚀 创建目标 Task: %@", request.URL);
        
        // 3. 获取 Task 当前的 Delegate
        id currentDelegate = [task delegate];
        
        // 4. 如果 Delegate 存在且不是我们自己的，就包装它
        if (currentDelegate && ![currentDelegate isKindOfClass:[MyCustomDelegate class]]) {
            MyCustomDelegate *wrapper = [[MyCustomDelegate alloc] initWithOriginalDelegate:currentDelegate];
            // 5. 强制替换 Delegate
            // 注意：虽然 NSURLSessionTask 没有公开的 setDelegate，但在 iOS 内部实现中，
            // 我们可以通过 KVC 或者直接调用私有方法，或者利用 objc_setAssociatedObject 来欺骗
            // 但最稳妥的方式是利用 Runtime 的 `class_replaceMethod` 或者 Hook 内部私有类。
            // 不过，对于大多数情况，直接尝试设置（如果系统允许）或者 Hook 内部私有 Task 类更有效。
            
            // 这里使用一个 Trick：直接尝试设置 Delegate (部分系统版本允许)
            // 如果这行不起作用，说明系统保护了该属性，需要 Hook 私有类 __NSURLSessionLocal
            [task setValue:wrapper forKey:@"delegate"]; 
        }
    }
    
    return task;
}

%end
