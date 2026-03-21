#import <Foundation/Foundation.h>
#import <objc/runtime.h> // 需要 runtime 来获取关联对象

// 定义一个常量来标记原始代理
static char kOriginalDelegateKey;

// --- 1. 定义判断逻辑 ---
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    // ⚠️ 替换为你的目标 URL 关键字
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}

// --- 2. 核心 Hook 逻辑 ---

%hook NSURLSession

// Hook 创建 Task 的方法
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    // 调用原始方法创建 Task
    NSURLSessionDataTask *task = %orig(request, completionHandler);

    // 如果是目标请求，处理代理
    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 拦截到目标请求 (Delegate模式): %@", request.URL);

        // 1. 获取原始代理
        id originalDelegate = [task delegate];

        // 2. 设置我们自己的代理（可以是原始代理的子类，或者通过消息转发）
        // 这里使用 runtime 关联对象保存原始代理
        objc_setAssociatedObject(task, &kOriginalDelegateKey, originalDelegate, OBJC_ASSOCIATION_RETAIN);

        // 3. 设置 task 的 delegate 为我们自定义的代理对象
        // 注意：这里需要创建一个自定义的代理对象，或者使用 Method Swizzling 拦截代理方法
        // 为了简化，这里假设我们有一个自定义的代理类 MyCustomDelegate
        // MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:originalDelegate];
        // [task setDelegate:customDelegate];
    }

    return task;
}

%end

// --- 3. 拦截代理方法 ---

%hook NSURLSessionTask

// Hook 任务完成的方法（这是 Delegate 模式中最常见的回调）
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    // 获取原始代理
    id originalDelegate = objc_getAssociatedObject(task, &kOriginalDelegateKey);

    // 1. 构造伪造的数据
    // 这里构造一个空的 NSError 或者 nil，表示任务“成功”完成
    NSError *fakeError = nil; // 或者构造一个带有特定 code 的 error

    // 2. 调用原始代理的方法，传递伪造的数据
    if ([originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [originalDelegate URLSession:session task:task didCompleteWithError:fakeError];
    }
}

%end
