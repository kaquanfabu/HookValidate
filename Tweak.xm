#import <Foundation/Foundation.h>

#pragma mark - 构造 JSON（你可以后面再改结构）
NSData *buildJSON() {
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
        NSLog(@"[Hook] JSON 生成失败: %@", error);
        return nil;
    }
    return jsonData;
}

#pragma mark - 判断目标请求
BOOL isTarget(NSURLRequest *req) {
    NSString *urlString = req.URL.absoluteString;
    NSLog(@"[Hook] 检查 URL: %@", urlString);  // 打印请求 URL，用于调试

    // 使用更精确的匹配方式，确保只匹配特定请求
    return [urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL.absoluteString);

        // 直接使用原始请求，不需要拷贝
        NSURLRequest *req = request;

        // 创建新的处理回调
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            // 打印原始数据
            if (data) {
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[Hook] 原始返回: %@", str);
            }

            // 如果请求出错，返回原数据
            if (error) {
                NSLog(@"[Hook] 错误发生: %@", error);
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // 替换数据
            NSData *newData = buildJSON();
            if (!newData) {
                // 如果构建 JSON 数据失败，直接返回原数据
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // 打印修改后的数据
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[Hook] 修改后的返回: %@", [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]);
            });

            // 返回修改后的数据
            if (completionHandler) {
                completionHandler(newData, response, error);
            }
        };

        // 使用新的 session 执行请求
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:newHandler];
        [task resume];

        return task;  // 返回实际的任务，确保它被正确执行
    }

    return %orig(request, completionHandler);
}

%end