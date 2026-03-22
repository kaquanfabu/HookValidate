#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// 定义一个常量来标记原始代理
static char kOriginalDelegateKey;

// 定义一个常量来标记原始代理
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // 替换为你的目标 URL 关键字
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}

// Gzip 压缩
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

// 构造伪造的 JSON 数据
static NSData *fakeJsonData() {
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
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
    
    // 如果生成 JSON 数据失败，返回一个空数据
    if (error) {
        return nil;
    }

    // 返回 gzip 压缩的数据
    return gzipData(jsonData);
}

// 自定义代理类
@interface MyCustomDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, strong) id originalDelegate;  // 使用 strong 来避免野指针问题

- (instancetype)initWithOriginalDelegate:(id)delegate;

@end

@implementation MyCustomDelegate

- (instancetype)initWithOriginalDelegate:(id)delegate {
    self = [super init];
    if (self) {
        _originalDelegate = delegate;
    }
    return self;
}

// 处理任务完成的代理方法
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError * _Nullable)error {
    // 获取原始代理并调用原始代理方法
    @try {
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[Error] 捕获到异常: %@", exception);
    }
}

@end

// Hook NSURLSession 的创建 task 方法
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    // 调用原始方法创建 Task
    NSURLSessionDataTask *task = %orig(request, completionHandler);

    // 如果是目标请求，处理代理
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 拦截到目标请求 (Delegate模式): %@", request.URL);

        // 1. 获取原始代理
        id originalDelegate = [task delegate];

        // 2. 使用 runtime 关联对象保存原始代理
        objc_setAssociatedObject(task, &kOriginalDelegateKey, originalDelegate, OBJC_ASSOCIATION_RETAIN);

        // 3. 设置 task 的 delegate 为我们自定义的代理对象
        MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:originalDelegate];
        [task setDelegate:customDelegate];
    }

    return task;
}

%end

// Hook NSURLSessionTask 的代理方法
%hook NSURLSessionTask

// Hook 任务完成的方法（这是 Delegate 模式中最常见的回调）
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError * _Nullable)error {
    // 获取原始代理
    id originalDelegate = objc_getAssociatedObject(task, &kOriginalDelegateKey);

    // 构造伪造的数据
    NSData *fakeData = fakeJsonData();  // 返回伪造的 JSON 数据

    // 使用 @try-catch 块来捕获异常
    @try {
        // 调用原始代理的 didCompleteWithError 方法，传递 nil 错误
        if ([originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [originalDelegate URLSession:session task:task didCompleteWithError:nil];
        }

        // 确保原始代理实现了 didReceiveData 方法
        if ([originalDelegate respondsToSelector:@selector(URLSession:task:didReceiveData:)]) {
            // 注入伪造的数据
            [originalDelegate URLSession:session task:task didReceiveData:fakeData];
        } else {
            NSLog(@"[Warning] 原始代理未实现 didReceiveData: 方法");
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[Error] 捕获到异常: %@", exception);
    }
}