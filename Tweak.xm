#import <Foundation/Foundation.h>

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    return [urlString containsString:@"/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // --- 1. 保存原始的 completionHandler ---
        void (^originalCompletion)(NSData *, NSURLResponse *, NSError *) = completionHandler;

        // --- 2. 定义新的回调 ---
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = 
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            
            // 错误处理
            if (error) {
                NSLog(@"[Hook] ⚠️ 原始请求出错: %@", error);
                if (originalCompletion) {
                    originalCompletion(data, response, error);
                }
                return;
            }

            // --- 3. 构造伪造数据 ---
            // 确保格式正确
            NSString *modifiedResponseStr = @"{\"code\":0,\"message\":\"请求成功\",\"success\":true,\"timestamp\":1774093881179,\"data\":null}";
            NSData *newData = [modifiedResponseStr dataUsingEncoding:NSUTF8StringEncoding];

            // 打印日志
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 🔓 拦截并修改返回: %@", modifiedResponseStr);
            });

            // 调用原始回调，传递伪造数据
            if (originalCompletion) {
                originalCompletion(newData, response, nil);
            }
        };

        // --- 4. 创建任务 ---
        NSURLSessionDataTask *task = %orig(request, newHandler);

        // --- 5. Hook 代理回调 (关键步骤) ---
        // 检查任务是否有代理，如果有，就替换代理方法
        if (task.delegate) {
            // 使用 Method Swizzling 或者 KVO 来 Hook 代理方法
            // 这里用最简单的 Method Swizzling
            Class delegateClass = object_getClass(task.delegate);
            SEL originalSEL = @selector(URLSession:task:didCompleteWithError:);
            SEL swizzledSEL = @selector(swizzled_URLSession:task:didCompleteWithError:);

            Method originalMethod = class_getInstanceMethod(delegateClass, originalSEL);
            Method swizzledMethod = class_getInstanceMethod(delegateClass, swizzledSEL);

            if (originalMethod && swizzledMethod) {
                method_exchangeImplementations(originalMethod, swizzledMethod);
            }
        }

        // --- 6. 启动任务 ---
        if (task) {
            [task resume];
        }

        return task;
    }

    // 非目标请求，走原始逻辑
    return %orig(request, completionHandler);
}

// --- 7. 定义 Swizzled 代理方法 ---
- (void)swizzled_URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // 强制将错误设为 nil，确保 App 认为请求成功
    [self swizzled_URLSession:session task:task didCompleteWithError:nil];
}

%end
