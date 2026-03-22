#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <zlib.h>

// 定义关联对象 Key
static char kOriginalDelegateKey;

// 1. 判断是否为目标请求
static BOOL isTargetRequest(NSURLRequest *request) {
    if (!request || !request.URL) return NO;
    NSString *urlStr = [request.URL absoluteString];
    return [urlStr containsString:@"nwgt/web/api/v1/menu/validate"];
}

// 2. Gzip 压缩工具 (同上)
static NSData *gzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    z_stream strm = {0};
    strm.total_out = 0;
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;

    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15 + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];
    do {
        if (strm.total_out >= compressed.length) {
            [compressed increaseLengthBy:16384];
        }
        strm.next_out = ((Bytef *)compressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(compressed.length - strm.total_out);
    } while (deflate(&strm, Z_FINISH) == Z_OK);

    deflateEnd(&strm);
    [compressed setLength:strm.total_out];
    return compressed;
}

// 3. Gzip 解压缩工具 (新增)
static NSData *ungzipData(NSData *data) {
    if (!data || data.length == 0) return nil;
    z_stream strm = {0};
    strm.next_in = (Bytef *)data.bytes;
    strm.avail_in = (uInt)data.length;
    strm.total_out = 0;

    if (inflateInit2(&strm, (15 + 16)) != Z_OK) {
        return nil;
    }

    NSMutableData *decompressed = [NSMutableData dataWithLength:16384];
    do {
        if (strm.total_out >= decompressed.length) {
            [decompressed increaseLengthBy:16384];
        }
        strm.next_out = ((Bytef *)decompressed.mutableBytes) + strm.total_out;
        strm.avail_out = (uInt)(decompressed.length - strm.total_out);
    } while (inflate(&strm, Z_FINISH) == Z_OK);

    inflateEnd(&strm);
    [decompressed setLength:strm.total_out];
    return decompressed;
}

// 4. 修改数据逻辑 (重点修改处)
static NSData *modifyData(NSData *originalData, NSURLSessionTask *task) {
    // 1. 解压缩
    NSData *decompressedData = ungzipData(originalData);
    if (!decompressedData) {
        NSLog(@"[Error] 解压缩失败");
        return originalData; // 解压失败则返回原数据
    }

    // 2. 解析 JSON
    NSError *error = nil;
    id jsonResponse = [NSJSONSerialization JSONObjectWithData:decompressedData options:0 error:&error];
    if (error) {
        NSLog(@"[Error] JSON 解析失败: %@", error);
        return originalData;
    }

    // 3. 修改逻辑 (根据你的需求修改这里)
    // 假设服务器返回的是字典，且有一个 "data" 字段
    if ([jsonResponse isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *dict = (NSMutableDictionary *)jsonResponse;

        // 示例1: 强制修改 code 为 0 (成功)
        dict[@"code"] = @0;

        // 示例2: 修改 message
        dict[@"message"] = @"拦截成功";

        // 示例3: 修改 data 中的某个字段 (需要根据实际返回结构调整)
        // 假设 data 是一个字典
        if ([dict[@"data"] isKindOfClass:[NSMutableDictionary class]]) {
            NSMutableDictionary *dataDict = dict[@"data"];
            // 比如把价格改成 0.01
            dataDict[@"price"] = @0.01;
        }

        // 示例4: 如果 data 是数组，遍历修改
        // if ([dict[@"data"] isKindOfClass:[NSMutableArray class]]) {
        //     for (NSMutableDictionary *item in dict[@"data"]) {
        //         item[@"stock"] = @999;
        //     }
        // }
    }

    // 4. 重新序列化
    NSData *modifiedJsonData = [NSJSONSerialization dataWithJSONObject:jsonResponse options:0 error:nil];
    if (!modifiedJsonData) {
        return originalData;
    }

    // 5. 重新压缩
    return gzipData(modifiedJsonData);
}

// 6. 自定义代理类 (核心 Hook)
@interface MyCustomDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (nonatomic, strong) id<NSURLSessionDataDelegate> originalDelegate;
- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate;
@end

@implementation MyCustomDelegate

- (instancetype)initWithOriginalDelegate:(id<NSURLSessionDataDelegate>)delegate {
    self = [super init];
    if (self) {
        _originalDelegate = delegate;
    }
    return self;
}

// Hook 这个方法，这是数据到达的地方
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // 检查是否为目标请求
    if (isTargetRequest(dataTask.originalRequest)) {
        NSLog(@"[Hook] 🎯 拦截到数据流，正在修改...");

        // 调用修改函数
        NSData *newData = modifyData(data, dataTask);

        // 调用原始代理的这个方法，但是传入我们修改后的数据
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:newData];
        }
    } else {
        // 非目标请求，直接放行原始数据
        if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
            [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:data];
        }
    }
}

// 为了保险起见，也 Hook 完成回调，防止 App 在这里做校验
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
    }
}

@end

// 7. Hook NSURLSession 创建任务 (同上)
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSURLSessionDataTask *task = %orig(request, completionHandler);

    id originalDelegate = [task delegate];
    if (originalDelegate) {
        // 保存原始代理
        objc_setAssociatedObject(task, &kOriginalDelegateKey, originalDelegate, OBJC_ASSOCIATION_RETAIN);

        // 替换代理
        MyCustomDelegate *customDelegate = [[MyCustomDelegate alloc] initWithOriginalDelegate:originalDelegate];
        [task setDelegate:customDelegate];
    }

    return task;
}

%end
