#import <Foundation/Foundation.h>

static NSMutableDictionary *dataMap;

#pragma mark - 构造返回 JSON
static NSData *buildJSON() {
    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @1773899566825
    };

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

%hook NSURLSession

- (instancetype)init {
    self = %orig;
    if (self) {
        dataMap = [NSMutableDictionary dictionary];  // 初始化缓存
    }
    return self;
}

#pragma mark - 收包（分段接收）
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

        // 缓存每次接收到的分段数据
        [cache appendData:data];

        // ❗ 不让原数据往下走
        return;
    }

    %orig(session, task, data);
}

#pragma mark - 请求完成（拼接数据并返回）
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    NSString *url = task.currentRequest.URL.absoluteString;

    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        NSNumber *key = @((uintptr_t)task);
        NSMutableData *cache = dataMap[key];

        if (cache) {
            NSString *origin = [[NSString alloc] initWithData:cache encoding:NSUTF8StringEncoding];
            NSLog(@"[Hook] 原始返回: %@", origin);

            // 拼接所有的分段数据
            NSData *newData = buildJSON();  // 这里是你自己构造的伪数据

            NSLog(@"[Hook] ✅ 拼接并替换返回");

            // 模拟回传
            dispatch_async(dispatch_get_main_queue(), ^{
                // 调用完成回调
                %orig(session, (NSURLSessionDataTask *)task, newData);
            });

            // 清除缓存
            [dataMap removeObjectForKey:key];
            return;
        }
    }

    %orig(session, task, error);
}

%end