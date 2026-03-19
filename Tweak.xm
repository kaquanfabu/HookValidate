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

#pragma mark - 递归删除字段

id RemoveKey(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [obj mutableCopy];
        [dict removeObjectForKey:@"isFiveVerif"];
        for (id key in dict.allKeys) {
            dict[key] = RemoveKey(dict[key]);
        }
        return dict;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *arr = [obj mutableCopy];
        for (NSInteger i = 0; i < arr.count; i++) {
            arr[i] = RemoveKey(arr[i]);
        }
        return arr;
    }
    return obj;
}

#pragma mark - Hook URLSession delegate

%hook NSObject

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSData *workingData = data;
    BOOL isGzip = NO;

    NSString *encoding = dataTask.response.allHeaderFields[@"Content-Encoding"];
    if ([encoding.lowercaseString containsString:@"gzip"]) {
        isGzip = YES;
        NSData *decompressed = gzipDecompress(data);
        if (decompressed) workingData = decompressed;
    }

    NSData *newData = workingData;

    @try {
        id json = [NSJSONSerialization JSONObjectWithData:workingData options:0 error:nil];
        if (json) {
            id newJson = RemoveKey(json);
            newData = [NSJSONSerialization dataWithJSONObject:newJson options:0 error:nil];
        }
    } @catch (NSException *e) {
        NSLog(@"[Hook] JSON parse error: %@", e);
    }

    if (isGzip) {
        NSData *compressed = gzipCompress(newData);
        if (compressed) newData = compressed;
    }

    %orig(session, dataTask, newData);
}

%end