#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

// 1. 声明一个私有协议，用于处理任务完成的回调
@protocol URLSessionTaskDelegateHook <NSURLSessionTaskDelegate>
@end

// 2. 实现协议的私有 Category
@interface NSURLSessionTask (Hook) <URLSessionTaskDelegateHook>
@end

@implementation NSURLSessionTask (Hook)

// 这是代理方法的实现，当任务完成时会调用这里
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // 在这里处理状态更新逻辑
    // 如果你需要让 App 认为成功，可以忽略 error 或者传入 nil
    // 注意：这里不能直接用 %orig，因为这是 Category 实现
    // 我们通过消息转发来调用原始实现
    [self forwardInvocation:[NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(URLSession:task:didCompleteWithError:)]]];
}

@end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 定义新的回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            // --- 构造伪造数据 ---
            NSString *modifiedResponseStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"data\":null}";
            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

            // --- 调用原始回调 ---
            if (completionHandler) {
                completionHandler(newData, response, nil);
            }
        };

        // --- 执行原始逻辑，获取任务对象 ---
        NSURLSessionDataTask *task = %orig(request, newHandler);

        if (task) {
            // --- 关键修复：设置任务的代理为当前任务自身 ---
            // 这样当系统调用代理方法时，就会进入上面的 Category 实现
            task.delegate = (id<NSURLSessionTaskDelegate>)task;

            [task resume];
        }

        return task;
    }

    // 不是目标请求，走原始逻辑
    return %orig(request, completionHandler);
}

%end
