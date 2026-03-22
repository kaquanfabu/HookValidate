#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// 定义一个常量来标记原始代理
static char kOriginalDelegateKey;

// 定义一个常量来标记原始代理
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // ⚠️ 替换为你的目标 URL 关键字
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}

// 自定义代理类
@interface MyCustomDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (nonatomic, assign) id originalDelegate;  // 使用 assign 而不是 weak

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
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
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
didCompleteWithError:(__nullable NSError *)error {
    // 获取原始代理
    id originalDelegate = objc_getAssociatedObject(task, &kOriginalDelegateKey);

    // 1. 构造伪造的数据
    NSError *fakeError = nil; // 或者构造一个带有特定 code 的 error

    // 2. 使用 @try-catch 块来捕获异常
    @try {
        // 3. 调用原始代理的方法，传递伪造的数据
        if ([originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
            [originalDelegate URLSession:session task:task didCompleteWithError:fakeError];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[Error] 捕获到异常: %@", exception);
    }
}

%end