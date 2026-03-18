#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define REMOVE_FIELD @"isFiveVerif"

@interface JsonHookProtocol : NSURLProtocol
@property(nonatomic,strong) NSURLSessionDataTask *task;
@end

#pragma mark - 递归删除JSON字段

void RemoveKeyRecursive(id obj)
{
    if ([obj isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary *dict = (NSMutableDictionary *)obj;

        if (dict[REMOVE_FIELD])
        {
            [dict removeObjectForKey:REMOVE_FIELD];
        }

        for (id key in [dict allKeys])
        {
            RemoveKeyRecursive(dict[key]);
        }
    }

    else if ([obj isKindOfClass:[NSArray class]])
    {
        for (id item in (NSArray *)obj)
        {
            RemoveKeyRecursive(item);
        }
    }
}

NSData *ProcessJSON(NSData *data)
{
    NSError *error = nil;

    id json =
    [NSJSONSerialization JSONObjectWithData:data
                                    options:NSJSONReadingMutableContainers
                                      error:&error];

    if (!json || error)
        return data;

    RemoveKeyRecursive(json);

    NSData *newData =
    [NSJSONSerialization dataWithJSONObject:json
                                    options:0
                                      error:nil];

    NSLog(@"[JSON HOOK] removed key: %s", REMOVE_FIELD);

    return newData;
}

@implementation JsonHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;

    if ([url hasPrefix:@"http"])
    {
        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSURLSessionConfiguration *config =
    [NSURLSessionConfiguration defaultSessionConfiguration];

    NSURLSession *session =
    [NSURLSession sessionWithConfiguration:config];

    __weak typeof(self) weakSelf = self;

    self.task =
    [session dataTaskWithRequest:self.request
               completionHandler:^(NSData *data,
                                   NSURLResponse *response,
                                   NSError *error)
    {

        if (data)
        {
            data = ProcessJSON(data);
        }

        [weakSelf.client URLProtocol:weakSelf
                 didReceiveResponse:response
                 cacheStoragePolicy:NSURLCacheStorageNotAllowed];

        if (data)
            [weakSelf.client URLProtocol:weakSelf didLoadData:data];

        [weakSelf.client URLProtocolDidFinishLoading:weakSelf];

    }];

    [self.task resume];
}

- (void)stopLoading
{
    [self.task cancel];
}

@end


#pragma mark - 注入 Session

%hook NSURLSessionConfiguration

- (void)setProtocolClasses:(NSArray *)protocolClasses
{
    NSMutableArray *arr = [protocolClasses mutableCopy];

    if (![arr containsObject:[JsonHookProtocol class]])
    {
        [arr insertObject:[JsonHookProtocol class] atIndex:0];
    }

    %orig(arr);
}

%end


#pragma mark - 调试打印

%hook NSURLSessionTask

- (void)resume
{
    NSLog(@"[REQUEST] %@", self.currentRequest.URL);
    %orig;
}

%end


#pragma mark - 初始化

%ctor
{
    NSLog(@"[JSON HOOK] Loaded");

    [NSURLProtocol registerClass:[JsonHookProtocol class]];
}