#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 压缩
NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    if (deflateInit2(&strm,
                     Z_DEFAULT_COMPRESSION,
                     Z_DEFLATED,
                     15 + 16,   // gzip
                     8,
                     Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    int status;
    do {
        if (strm.total_out >= compressed.length) compressed.length += 16384;
        strm.next_out = (Bytef *)compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
        status = deflate(&strm, Z_FINISH);
    } while (status == Z_OK);

    deflateEnd(&strm);
    if (status != Z_STREAM_END) return nil;
    compressed.length = strm.total_out;
    return compressed;
}

#pragma mark - 构造 JSON
NSData *buildJSON() {
    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(timestamp)
    };

    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
}

#pragma mark - 目标判断
BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"];
}

#pragma mark - NSURLSession Hook（gzip 模拟 + SSL 绕过）
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {
        NSLog(@"[Hook] 🎯 命中目标接口");

        NSData *jsonData = buildJSON();
        NSData *gzipData = gzipCompress(jsonData);

        NSDictionary *headers = @{
            @"Content-Type": @"application/json;charset=UTF-8",
            @"Content-Encoding": @"gzip",
            @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)gzipData.length]
        };

        NSHTTPURLResponse *resp =
        [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:headers];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(gzipData, resp, nil);
        });

        return nil; // 完全拦截
    }

    return %orig(request, completionHandler);
}

#pragma mark - SSL 绕过
- (void)URLSession:(NSURLSession *)session
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
          completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    %orig(session, challenge, completionHandler);
}

%end

#pragma mark - NSURLSessionTask Hook（兼容 Alamofire delegate）
%hook NSURLSessionTask

- (void)setState:(NSURLSessionTaskState)state {
    %orig;

    if (state == NSURLSessionTaskStateCompleted) {
        NSURLRequest *req = self.currentRequest;
        if (!isTarget(req)) return;

        NSData *jsonData = buildJSON();
        NSData *gzipData = gzipCompress(jsonData);

        if ([self respondsToSelector:@selector(setValue:forKey:)]) {
            @try {
                [self setValue:gzipData forKey:@"_responseData"];
            } @catch (NSException *exception) {
                NSLog(@"[Hook] KVC _responseData failed: %@", exception);
            }
        }
    }
}

%end

#pragma mark - NSURLConnection Hook（兼容旧版网络库）
%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    if (isTarget(request)) return YES;
    return %orig;
}

%end