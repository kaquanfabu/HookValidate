#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// 定义关联对象 Key
static char kOriginalDelegateKey;

// 1. 判断是否为目标请求
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // 请确保这里的关键字准确
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}

// 2. Gzip 压缩工具
static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    
    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    // 15+16 表示使用 gzip 格式
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

// 3. 构造伪造数据
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
    
    if (error) {
        NSLog(@"[Error] JSON 序列化失败: %@", error);
        return nil;
    }

    return gzipData(jsonData);
}

// 4. 自定义代理类
@interface MyCustomDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
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

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError * _Nullable)error {
    @try {
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
        }
    } @catch (NSException *exception) {
        NSLog(@"[Error] 代理回调异常: %@", exception);
    }
}
@end

// 5. Hook NSURLSession 创建任务
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSURLSessionDataTask *task = %orig(request, completionHandler);

    // 仅处理目标请求
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 拦截到目标请求: %@", request.URL);

        id originalDelegate = [task delegate];
        // 保存原始代理
        objc_setAssociatedObject(task, &kOriginalDelegateKey, originalDelegate, OBJC_ASSOCIATION_RETAIN);

        // 替换代理
        MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:originalDelegate];
        [task setDelegate:customDelegate];
    }

    return task;
}
%end

// 6. Hook 任务完成回调
%hook NSURLSessionTask

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError * _Nullable)error {
    
    // 获取原始代理
    id originalDelegate = objc_getAssociatedObject(task, &kOriginalDelegateKey);

    @try {
        // 只有当存在原始代理且是 DataDelegate 时才处理
        if (originalDelegate && [originalDelegate conformsToProtocol:@protocol(NSURLSessionDataDelegate)]) {
            
            // 1. 发送伪造数据
            // 检查是否为 DataTask，避免 DownloadTask 等误入
            if ([task isKindOfClass:[NSURLSessionDataTask class]]) {
                NSData *fakeData = fakeJsonData();
                
                if (fakeData) {
                    SEL selector = @selector(URLSession:task:didReceiveData:);
                    // 获取方法签名
                    NSMethodSignature *signature = [originalDelegate methodSignatureForSelector:selector];
                    
                    if (signature) {
                        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                        [invocation setTarget:originalDelegate];
                        [invocation setSelector:selector];
                        
                        // 设置参数 (索引从2开始)
                        // 注意：这里直接传入变量的地址是安全的
                        [invocation setArgument:&session atIndex:2];
                        [invocation setArgument:&task atIndex:3];
                        [invocation setArgument:&fakeData atIndex:4];
                        
                        [invocation invoke];
                        NSLog(@"[Hook] ✅ 已注入伪造数据 (长度: %lu)", (unsigned long)fakeData.length);
                    }
                } else {
                    NSLog(@"[Hook] ⚠️ 伪造数据生成失败，跳过数据注入");
                }
            }

            // 2. 通知任务完成 (传递 nil 表示成功)
            if ([originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
                [originalDelegate URLSession:session task:task didCompleteWithError:nil];
                NSLog(@"[Hook] ✅ 已通知任务完成");
            }
        } else {
            // 如果不是目标请求或没有关联对象，调用原始实现
            %orig;
        }
    } @catch (NSException *exception) {
        NSLog(@"[Error] 捕获到异常: %@", exception);
        // 发生异常时，最好还是调用原始实现，防止逻辑中断
        %orig;
    }
}
%end
