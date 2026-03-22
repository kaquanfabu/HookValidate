#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h> // Gzip 压缩

// 判断目标接口
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *url = request.URL.absoluteString;
    return [url containsString:@"nwgt/web/api/v1/menu/validate"];
}

// Gzip 压缩
static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;

    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    int ret = deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                           (15+16), 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) return nil;

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];
    do {
        if (strm.total_out >= compressed.length)
            [compressed increaseLengthBy:16384];

        // ⚠️ 修复：先转 Bytef* 再加偏移
        strm.next_out = ((Bytef *)compressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);

        ret = deflate(&strm, Z_FINISH);
    } while (ret == Z_OK);

    if (deflateEnd(&strm) != Z_OK) return nil;

    [compressed setLength:strm.total_out];
    return compressed;
}
// 构造原始接口 JSON 并 Gzip
static NSData *fakeGzipData() {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSDictionary *obj = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @(ts)
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return gzipData(json);
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {

    if (isTargetRequest(request)) {
        NSLog(@"[Hook] 🎯 命中接口: %@", request.URL);

        NSData *data = fakeGzipData();

        NSHTTPURLResponse *resp =
        [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                   statusCode:200
                                  HTTPVersion:@"HTTP/1.1"
                                 headerFields:@{@"Content-Type": @"application/json",
                                                @"Content-Encoding": @"gzip"}];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(data, resp, nil);
        });

        return nil; // 不走原请求
    }

    return %orig;
}

%end

%hook NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    if (isTargetRequest(dataTask.currentRequest)) {
        NSHTTPURLResponse *fakeResp =
        [[NSHTTPURLResponse alloc] initWithURL:dataTask.currentRequest.URL
                                   statusCode:200
                                  HTTPVersion:@"HTTP/1.1"
                                 headerFields:@{@"Content-Type": @"application/json",
                                                @"Content-Encoding": @"gzip"}];
        %orig(session, dataTask, fakeResp, completionHandler);
        completionHandler(NSURLSessionResponseAllow);
        return;
    }

    %orig;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {

    if (isTargetRequest(dataTask.currentRequest)) {
        NSData *fake = fakeGzipData();
        %orig(session, dataTask, fake);
        return;
    }

    %orig;
}

%end

%hook NSURLSessionTask

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {

    if (isTargetRequest(task.currentRequest)) {
        %orig(session, task, nil);
        return;
    }

    %orig;
}

%end