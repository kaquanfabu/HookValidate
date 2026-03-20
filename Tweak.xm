#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 压缩（稳定版）
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
        if (strm.total_out >= compressed.length) {
            compressed.length += 16384;
        }

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

#pragma mark - 核心 Hook（完全模拟服务器）
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {

        NSLog(@"[Hook] 🎯 命中目标接口");

        // 1️⃣ 构造 JSON
        NSData *jsonData = buildJSON();

        // 2️⃣ gzip 压缩
        NSData *gzipData = gzipCompress(jsonData);

        // 3️⃣ 构造 HTTP 响应（关键）
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

        // 4️⃣ 直接回调（不走网络）
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(gzipData, resp, nil);
        });

        return nil; // ❗完全拦截
    }

    return %orig(request, completionHandler);
}

%end

#pragma mark - SSL 绕过（关键）
%hook NSURLSession (SSLBypass)

- (void)URLSession:(NSURLSession *)session
        didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
          completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {

        NSURLCredential *cred =
        [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];

        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    %orig(session, challenge, completionHandler);
}

%end