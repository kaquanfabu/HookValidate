#import <Foundation/Foundation.h>

#pragma mark - 声明并初始化 dataMap
static NSMutableDictionary *dataMap;  // 声明全局缓存变量

#pragma mark - 构造返回 JSON
static NSData *buildJSON() {
    NSDictionary *obj = @{
        @"sing": [NSNull null], 
        @"data": @{ @"validateItem": @"0,1,2,3,4" },  // 模拟 validateItem 数据
        @"code": @0,  // 状态码 0 表示成功
        @"message": @"请求成功",  // 请求成功的消息
        @"success": @YES,  // 请求是否成功
        @"skey": [NSNull null], 
        @"timestamp": @1774086299586  // 时间戳
    };

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

%hook NSURLSession

// 初始化方法
- (instancetype)init {
    self = %orig;
    if (self) {
        dataMap = [NSMutableDictionary dictionary];  // 初始化缓存字典
    }
    return self;
}

#pragma mark - 收包（没有分段，直接接收完整数据）
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {

    NSString *url = task.currentRequest.URL.absoluteString;

    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        NSNumber *key = @((uintptr_t)task);

        // 创建一个缓存数据
        NSMutableData *cache = dataMap[key];
        if (!cache) {
            cache = [NSMutableData data];
            dataMap[key] = cache;
        }

        // 缓存接收到的数据
        [cache appendData:data];

        // ❗ 不让原数据往下走
        return;
    }

    %orig(session, task, data);
}

#pragma mark - 请求完成（直接返回模拟的 JSON 数据）
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    NSString *url = task.currentRequest.URL.absoluteString;

    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        NSNumber *key = @((uintptr_t)task);
        NSMutableData *cache = dataMap[key];

        if (cache) {
            // 直接使用 buildJSON() 返回伪数据
            NSData *newData = buildJSON();  // 这里是你自己构造的伪数据

            NSLog(@"[Hook] ✅ 返回模拟数据");

            // 模拟回调并传递 newData
            dispatch_async(dispatch_get_main_queue(), ^{
                // 创建一个新的响应，模拟请求完成
                NSURLResponse *response = task.response;
                NSError *completionError = nil;

                // 调用模拟的 completionHandler，返回模拟数据
                if (!error) {
                    // 模拟成功完成
                    [session dataTaskWithRequest:task.currentRequest
                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                            // 使用 newData 作为模拟的返回数据
                            data = newData;
                            completionHandler(data, response, completionError); // 使用模拟数据
                        }];
                }
            });

            // 清除缓存
            [dataMap removeObjectForKey:key];
            return;
        }
    }

    // 如果没有特殊处理，继续正常处理
    %orig(session, task, error);
}

%end