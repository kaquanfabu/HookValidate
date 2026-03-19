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

#pragma mark - 全局缓存每个 dataTask 的分片数据

static NSMutableDictionary<NSNumber *, NSMutableData *> *taskDataCache;

__attribute__((constructor))
static void initCache() {
    taskDataCache = [NSMutableDictionary dictionary];
}

#pragma mark - Hook URLSession delegate (拼接分片 + 完整替换)

%hook NSObject

// 收到分片数据
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSNumber *taskId = @((uintptr_t)dataTask);

    NSMutableData *buffer = taskDataCache[taskId];
    if (!buffer) {
        buffer = [NSMutableData data];
        taskDataCache[taskId] = buffer;
    }
    [buffer appendData:data];

    %orig(session, dataTask, data); // 让系统继续处理原始分片
}

// 请求完成
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    NSNumber *taskId = @((uintptr_t)task);
    NSMutableData *buffer = taskDataCache[taskId];
    if (buffer) {
        NSData *workingData = buffer;
        BOOL isGzip = NO;

        NSHTTPURLResponse *httpResponse = nil;
        if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)task.response;
        }

        if (httpResponse) {
            NSString *encoding = httpResponse.allHeaderFields[@"Content-Encoding"];
            if ([encoding.lowercaseString containsString:@"gzip"]) {
                isGzip = YES;
                NSData *decompressed = gzipDecompress(buffer);
                if (decompressed) workingData = decompressed;
            }
        }

        NSString *urlString = task.currentRequest.URL.absoluteString;
        if ([urlString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/five/verif/position"]) {
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

            workingData = [NSJSONSerialization dataWithJSONObject:fixedResponse options:0 error:nil];
        }

        if (isGzip) {
            NSData *compressed = gzipCompress(workingData);
            if (compressed) workingData = compressed;
        }

        // 替换原始缓存数据，确保 Alamofire 最终使用
        [buffer setData:workingData];

        // 删除缓存
        [taskDataCache removeObjectForKey:taskId];
    }

    %orig(session, task, error);
}

%end