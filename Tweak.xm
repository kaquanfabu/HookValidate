#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <zlib.h>

#pragma mark - gzip

NSData *gzipDecompress(NSData *data) {
    if (!data || data.length == 0) return data;

    unsigned full = (unsigned)data.length;
    unsigned half = (unsigned)data.length / 2;

    NSMutableData *out = [NSMutableData dataWithLength:full + half];

    z_stream strm;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;

    if (inflateInit2(&strm, (15+32)) != Z_OK) return nil;

    while (1) {
        if (strm.total_out >= out.length)
            out.length += half;

        strm.next_out = out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);

        int status = inflate(&strm, Z_SYNC_FLUSH);

        if (status == Z_STREAM_END) break;
        if (status != Z_OK) return nil;
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

        strm.next_out = out.mutableBytes + strm.total_out;
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

#pragma mark - fake data

NSData *buildFakeData(void) {
    NSDictionary *json = @{
        @"sing": [NSNull null],
        @"data": [NSNull null],
        @"code": @0,
        @"message": @"请求成功",
        @"success": @YES,
        @"skey": [NSNull null],
        @"timestamp": @((long long)([[NSDate date] timeIntervalSince1970]*1000))
    };
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
}

#pragma mark - log

void logx(NSString *s) {
    NSLog(@"[Hook] %@", s);
}

#pragma mark - SSL bypass

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

#pragma mark - 🔥 核心底层拦截

%hook NSObject

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSURLRequest *req = dataTask.originalRequest;
    NSString *url = req.URL.absoluteString;

    NSData *newData = data;

    if ([dataTask.response isKindOfClass:[NSHTTPURLResponse class]]) {

        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)dataTask.response;

        if ([url containsString:@"/menu/validate"]) {

            logx([NSString stringWithFormat:@"🔥 HIT %@", url]);

            // 解 gzip
            if (isGzip(resp)) {
                NSData *de = gzipDecompress(data);
                if (de) newData = de;
            }

            // 替换
            newData = buildFakeData();

            // 压回 gzip
            if (isGzip(resp)) {
                NSData *re = gzipCompress(newData);
                if (re) newData = re;
            }
        }
    }

    %orig(session, dataTask, newData);
}

%end

#pragma mark - ctor

%ctor {
    NSLog(@"[Tweak] Low-level Hook Loaded");
}