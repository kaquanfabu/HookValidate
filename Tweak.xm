#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>
#import <objc/runtime.h>

#pragma mark - gzip

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;

    unsigned full = (unsigned)data.length;
    unsigned half = (unsigned)data.length / 2;

    NSMutableData *out = [NSMutableData dataWithLength:full + half];

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    if (inflateInit2(&strm, (15+32)) != Z_OK) return nil;

    while (1) {
        if (strm.total_out >= out.length)
            out.length += half;

        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);

        int status = inflate(&strm, Z_SYNC_FLUSH);

        if (status == Z_STREAM_END) break;
        if (status != Z_OK) {
            inflateEnd(&strm);
            return nil;
        }
    }

    inflateEnd(&strm);
    out.length = strm.total_out;
    return out;
}

NSData *gzipCompress(NSData *data) {
    if (!data || data.length == 0) return data;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;

    NSMutableData *out = [NSMutableData dataWithLength:16384];

    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    do {
        if (strm.total_out >= out.length)
            out.length += 16384;

        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);

        deflate(&strm, Z_FINISH);

    } while (strm.avail_out == 0);

    deflateEnd(&strm);

    out.length = strm.total_out;
    return out;
}

BOOL isGzip(NSHTTPURLResponse *resp) {
    NSString *e = resp.allHeaderFields[@"Content-Encoding"];
    return e && [e.lowercaseString containsString:@"gzip"];
}

#pragma mark - fake

NSData *buildFakeData(void) {
    NSDictionary *json = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970]*1000))
    };
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
}

#pragma mark - 关联对象key

static const void *kBufferKey = &kBufferKey;

#pragma mark - Hook

%hook NSObject

// 🔹 收数据（拼包）
- (void)urlSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSMutableData *buffer = objc_getAssociatedObject(dataTask, kBufferKey);

    if (!buffer) {
        buffer = [NSMutableData data];
        objc_setAssociatedObject(dataTask, kBufferKey, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [buffer appendData:data];

    // ❗这里不改数据
    %orig(session, dataTask, data);
}

// 🔥 最终回调（核心改包点）
- (void)urlSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    NSMutableData *buffer = objc_getAssociatedObject(task, kBufferKey);

    if (buffer && task.originalRequest) {

        NSString *url = task.originalRequest.URL.absoluteString;

        if ([url containsString:@"/menu/validate"]) {

            NSLog(@"🔥 FINAL HIT %@", url);

            NSData *finalData = buffer;

            if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {

                NSHTTPURLResponse *resp = (NSHTTPURLResponse *)task.response;

                // 解 gzip
                if (isGzip(resp)) {
                    NSData *de = gzipDecompress(buffer);
                    if (de) finalData = de;
                }

                // 替换
                finalData = buildFakeData();

                // 压回 gzip
                if (isGzip(resp)) {
                    NSData *re = gzipCompress(finalData);
                    if (re) finalData = re;
                }
            }

            // ❗关键：替换 buffer 内容
            [buffer setData:finalData];
        }
    }

    %orig(session, task, error);
}

%end

#pragma mark - SSL 绕过

%hook NSURLSession

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
        return;
    }

    %orig(session, challenge, completionHandler);
}

%end

#pragma mark - ctor

%ctor {
    NSLog(@"[Tweak] 🚀 Ultimate Hook Loaded");
}