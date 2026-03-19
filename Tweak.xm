#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 解压

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;

    unsigned full_length = (unsigned)data.length;
    unsigned half_length = (unsigned)data.length / 2;

    NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];

    BOOL done = NO;
    int status;

    z_stream strm;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (unsigned)data.length;
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;

    if (inflateInit2(&strm, (15 + 32)) != Z_OK) return nil;

    while (!done) {
        if (strm.total_out >= decompressed.length)
            decompressed.length += half_length;

        strm.next_out = (Bytef *)decompressed.mutableBytes + strm.total_out;
        strm.avail_out = (unsigned)(decompressed.length - strm.total_out);

        status = inflate(&strm, Z_SYNC_FLUSH);

        if (status == Z_STREAM_END) {
            done = YES;
        } else if (status != Z_OK) {
            break;
        }
    }

    if (inflateEnd(&strm) != Z_OK) return nil;

    if (done) {
        decompressed.length = strm.total_out;
        return decompressed;
    }

    return nil;
}

#pragma mark - gzip 压缩

NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     (15 + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (unsigned)data.length;

    do {
        if (strm.total_out >= compressed.length)
            compressed.length += 16384;

        strm.next_out = (Bytef *)compressed.mutableBytes + strm.total_out;
        strm.avail_out = (unsigned)(compressed.length - strm.total_out);

        deflate(&strm, Z_FINISH);

    } while (strm.avail_out == 0);

    deflateEnd(&strm);
    compressed.length = strm.total_out;

    return compressed;
}

#pragma mark - 判断 gzip

BOOL isGzip(NSHTTPURLResponse *response) {
    NSString *encoding = response.allHeaderFields[@"Content-Encoding"];
    return [encoding.lowercaseString containsString:@"gzip"];
}

#pragma mark - 目标 URL 判断

BOOL isTarget(NSURLRequest *req) {
    return [req.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/five/verif/position"];
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

#pragma mark - NSURLSession (completionHandler)

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {

    if (isTarget(request)) {

        return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSData *newData = buildFakeData();

            if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

                if (isGzip(http)) {
                    newData = gzipCompress(newData);
                }
            }

            completionHandler(newData, response, error);
        });
    }

    return %orig;
}

%end

#pragma mark - Alamofire / Delegate 模式

%hook NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {

    NSURLRequest *req = dataTask.currentRequest;

    if (isTarget(req)) {

        NSData *newData = buildFakeData();

        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)dataTask.response;

        if (isGzip(resp)) {
            newData = gzipCompress(newData);
        }

        %orig(session, dataTask, newData);
        return;
    }

    %orig;
}

%end

#pragma mark - SSL Pinning 绕过

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
              didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
                completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    NSURLCredential *cred = [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
}

%end

#pragma mark - 防某些库（AFNetworking）

%hook NSURLConnection

+ (BOOL)canHandleRequest:(NSURLRequest *)request {
    return YES;
}

%end