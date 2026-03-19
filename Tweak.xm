#import <Foundation/Foundation.h>
#import <zlib.h>

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

#pragma mark - Hook NSURLSession

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler
{
    void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err){
        NSString *urlString = request.URL.absoluteString;
        if ([urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
            long long timestamp = (long long)([[NSDate date] timeIntervalSince1970]*1000);
            NSDictionary *fixedResponse = @{
                @"sing"      : [NSNull null],
                @"data"      : [NSNull null],
                @"code"      : @0,
                @"message"   : @"请求成功",
                @"success"   : @YES,
                @"skey"      : [NSNull null],
                @"timestamp" : @(timestamp)
            };
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fixedResponse options:0 error:nil];

            // 判断 gzip
            if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                NSString *encoding = [(NSHTTPURLResponse*)resp allHeaderFields][@"Content-Encoding"];
                if ([encoding.lowercaseString containsString:@"gzip"]) {
                    NSData *compressed = gzipCompress(jsonData);
                    if (compressed) jsonData = compressed;
                }
            }

            data = jsonData; // 替换返回
        }
        handler(data, resp, err);
    };

    return %orig(request, newHandler);
}

%end