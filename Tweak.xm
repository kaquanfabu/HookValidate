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

%hook SessionDelegate

// 初始化缓存
- (instancetype)init {
    self = %orig;
    if (self) {
        dataMap = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 收包（拦截数据流）
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {

    NSString *url = task.currentRequest.URL.absoluteString;

    if (url && [url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        NSNumber *key = @((uintptr_t)task);

        NSMutableData *cache = dataMap[key];
        if (!cache) {
            cache = [NSMutableData data];
            dataMap[key] = cache;
        }

        [cache appendData:data];

        // ❗ 拦截，不让原数据往下走
        return;
    }

    %orig(session, task, data);
}

#pragma mark - 请求完成（在这里改返回）
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    NSString *url = task.currentRequest.URL.absoluteString;

    if (url && [url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {

        NSNumber *key = @((uintptr_t)task);
        NSMutableData *cache = dataMap[key];

        if (cache) {

            NSString *origin = [[NSString alloc] initWithData:cache encoding:NSUTF8StringEncoding];
            NSLog(@"[Hook] 原始返回: %@", origin);

            NSData *newData = buildJSON();

            NSLog(@"[Hook] ✅ 已替换返回");

            // ✅ 关键：把“假数据”喂回 Alamofire
            %orig(session, (NSURLSessionDataTask *)task, newData);

            [dataMap removeObjectForKey:key];
            return;
        }
    }

    %orig(session, task, error);
}

%end