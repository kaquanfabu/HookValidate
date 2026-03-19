#import <Foundation/Foundation.h>
#import <objc/runtime.h>
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

#pragma mark - 自定义 NSURLProtocol

@interface HookURLProtocol : NSURLProtocol
@end

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if ([url containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/five/verif/position"]) {
        if ([NSURLProtocol propertyForKey:@"HookHandled" inRequest:request]) {
            return NO; // 避免重复处理
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"HookHandled" inRequest:mutableReq];

    // 构造固定 JSON 响应
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

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fixedResponse options:0 error:nil];

    // 判断是否需要 gzip
    BOOL shouldGzip = NO;
    NSString *acceptEncoding = [self.request valueForHTTPHeaderField:@"Accept-Encoding"];
    if ([acceptEncoding.lowercaseString containsString:@"gzip"]) {
        shouldGzip = YES;
        NSData *compressed = gzipCompress(jsonData);
        if (compressed) jsonData = compressed;
    }

    // 构造 HTTP 响应
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:shouldGzip ? @{@"Content-Encoding": @"gzip"} : nil];

    // 返回数据
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:jsonData];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 不需要做任何操作
}

@end

#pragma mark - 注册 NSURLProtocol

__attribute__((constructor))
static void registerHookProtocol() {
    [NSURLProtocol registerClass:[HookURLProtocol class]];
}