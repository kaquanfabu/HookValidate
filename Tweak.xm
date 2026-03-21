#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - Gzip 压缩
NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK)
        return nil;

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    int status;
    do {
        if (strm.total_out >= compressed.length)
            compressed.length += 16384;

        strm.next_out = (Bytef *)compressed.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);

        status = deflate(&strm, Z_FINISH);

    } while (status == Z_OK);

    deflateEnd(&strm);

    if (status != Z_STREAM_END) return nil;

    compressed.length = strm.total_out;
    return compressed;
}

#pragma mark - 构造 JSON 并 Gzip 压缩
NSData *buildAndCompressJSON() {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": @{
            @"validateItem": @"0"
        },
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(ts)
    };

    // 将字典转为 JSON 数据
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];

    // 使用 gzip 压缩 JSON 数据
    return gzipCompress(jsonData);
}

#pragma mark - 返回的 JSON 响应（带 Gzip 压缩）
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTarget(request)) {

        // 防止递归调用
        if ([request valueForHTTPHeaderField:@"X-Hooked"]) {
            return %orig(request, completionHandler);
        }

        NSMutableURLRequest *req = [request mutableCopy];
        [req setValue:@"1" forHTTPHeaderField:@"X-Hooked"];

        void (^newHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {

            NSLog(@"[Hook] 🎯 命中接口");

            // 如果有错误，原样返回
            if (error) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }

            // 获取并压缩 JSON 数据
            NSData *compressedData = buildAndCompressJSON();

            // 设置压缩后的数据和响应头
            NSDictionary *headers = @{
                @"Content-Type": @"application/json;charset=UTF-8",
                @"Content-Encoding": @"gzip"
            };

            NSHTTPURLResponse *resp =
            [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                        statusCode:200
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:headers];

            if (completionHandler) {
                completionHandler(compressedData, resp, nil);
            }
        };

        return %orig(req, newHandler);
    }

    return %orig(request, completionHandler);
}

%end