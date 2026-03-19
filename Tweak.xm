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
    if (!e) return NO;
    return [e.lowercaseString containsString:@"gzip"];
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

#pragma mark - 核心处理

NSData *processData(NSData *data, NSURLResponse *response, NSString *url) {

    if (!data || !response) return data;

    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return data;

    if (![url containsString:@"/menu/validate"]) return data;

    NSLog(@"🔥 HIT URL: %@", url);

    NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;

    NSData *newData = data;

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

    return newData;
}

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

#pragma mark - Alamofire Hook

%hook Alamofire.SessionDelegate

- (void)urlSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSString *url = dataTask.originalRequest.URL.absoluteString;

    NSData *newData = processData(data, dataTask.response, url);

    %orig(session, dataTask, newData);
}

%end

#pragma mark - AFNetworking Hook

%hook AFURLSessionManager

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            uploadProgress:(void *)uploadProgress
                          downloadProgress:(void *)downloadProgress
                         completionHandler:(void (^)(NSURLResponse *, id, NSError *))completionHandler
{
    void (^newCompletion)(NSURLResponse *, id, NSError *) =
    ^(NSURLResponse *response, id responseObject, NSError *error) {

        NSData *data = nil;

        if ([responseObject isKindOfClass:[NSData class]]) {
            data = responseObject;
        } else if ([responseObject isKindOfClass:[NSDictionary class]]) {
            data = [NSJSONSerialization dataWithJSONObject:responseObject options:0 error:nil];
        }

        NSString *url = request.URL.absoluteString;

        NSData *newData = processData(data, response, url);

        id newObj = newData;

        if (completionHandler)
            completionHandler(response, newObj, error);
    };

    return %orig(request, uploadProgress, downloadProgress, newCompletion);
}

%end

#pragma mark - 通杀 Delegate

%hook NSObject

- (void)urlSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    NSString *cls = NSStringFromClass([self class]);

    if (![cls containsString:@"Delegate"]) {
        return %orig;
    }

    NSString *url = dataTask.originalRequest.URL.absoluteString;

    NSData *newData = processData(data, dataTask.response, url);

    %orig(session, dataTask, newData);
}

%end

#pragma mark - NSURLSession 兜底

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler
{
    void (^newBlock)(NSData *, NSURLResponse *, NSError *) =
    ^(NSData *data, NSURLResponse *response, NSError *error) {

        NSString *url = request.URL.absoluteString;

        NSData *newData = processData(data, response, url);

        if (completionHandler)
            completionHandler(newData, response, error);
    };

    return %orig(request, newBlock);
}

%end

#pragma mark - WebView

%hook WKWebView

- (void)loadRequest:(NSURLRequest *)request {
    NSLog(@"🌐 WKWebView: %@", request.URL.absoluteString);
    %orig;
}

%end

#pragma mark - ctor

%ctor {
    NSLog(@"[Tweak] ✅ FULL HOOK LOADED");
}