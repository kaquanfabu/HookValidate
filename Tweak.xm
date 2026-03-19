#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip 解压/压缩

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;
    unsigned full_length = (unsigned)data.length;
    unsigned half_length = (unsigned)data.length / 2;
    NSMutableData *decompressed = [NSMutableData dataWithLength:full_length + half_length];
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

        if (status == Z_STREAM_END) done = YES;
        else if (status != Z_OK) break;
    }

    if (inflateEnd(&strm) != Z_OK) return nil;

    if (done) {
        decompressed.length = strm.total_out;
        return decompressed;
    }
    return nil;
}

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

#pragma mark - Hook URLSession delegate

%hook NSObject

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSData *newData = data;
    BOOL isGzip = NO;

    NSHTTPURLResponse *httpResponse = nil;
    if ([dataTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
        httpResponse = (NSHTTPURLResponse *)dataTask.response;
    }

    if (httpResponse) {
        NSString *encoding = httpResponse.allHeaderFields[@"Content-Encoding"];
        if ([encoding.lowercaseString containsString:@"gzip"]) {
            isGzip = YES;
            NSData *decompressed = gzipDecompress(data);
            if (decompressed) newData = decompressed;
        }
    }

    NSString *urlString = dataTask.currentRequest.URL.absoluteString;
    if ([urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        // 当前时间戳（毫秒）
        long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);

        NSDictionary *fixedResponse = @{
            @"sing"      : [NSNull null],
            @"data"      : [NSNull null],
            @"code"      : @0,
            @"message"   : @"请求成功",
            @"success"   : @YES,
            @"skey"      : [NSNull null],
            @"timestamp" : @(timestamp)
        };

        newData = [NSJSONSerialization dataWithJSONObject:fixedResponse options:0 error:nil];
    }

    if (isGzip) {
        NSData *compressed = gzipCompress(newData);
        if (compressed) newData = compressed;
    }

    %orig(session, dataTask, newData);
}

%end