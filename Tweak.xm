#import <Foundation/Foundation.h>

#pragma mark - 目标URL判断

BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - 构造假数据

NSData *buildFakeData() {
    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    NSDictionary *fake = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(timestamp)
    };

    return [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
}

#pragma mark - NSURLSession Hook (completionHandler + SSL Pinning)

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        __unsafe_unretained typeof(self) weakSelf = self;
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            __unsafe_unretained typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                // 直接返回未压缩的伪造数据
                NSData *newData = buildFakeData();
                
                // 调用原 completionHandler 返回未压缩的数据
                completionHandler(newData, response, error);
            }
        };

        return %orig(request, newHandler);  // <-- 用一个变量包裹 block
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - Alamofire / Delegate 模式（兼容）

%hook NSURLSessionTask

- (void)setState:(NSURLSessionTaskState)state {
    %orig;

    if (state == NSURLSessionTaskStateCompleted) {

        NSURLRequest *req = self.currentRequest;
        if (!isTarget(req)) return;

        NSData *newData = buildFakeData();
        
        // 直接返回未压缩的伪造数据
        // KVC 替换 responseData
        [self setValue:newData forKey:@"_responseData"];
    }
}

%end

#pragma mark - 防 AFNetworking / NSURLConnection

%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    if (isTarget(request)) return YES;
    return %orig;
}

%end