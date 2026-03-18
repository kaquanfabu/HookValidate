#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define REMOVE_FIELD @"isFiveVerif"

@interface JsonHookProtocol : NSURLProtocol
@property(nonatomic,strong) NSURLSessionDataTask *task;
@end


#pragma mark - 日志窗口

static UITextView *logView = nil;

void InitLogWindow()
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window)
            window = [UIApplication sharedApplication].windows.firstObject;

        logView = [[UITextView alloc] initWithFrame:CGRectMake(10,120,355,260)];

        logView.backgroundColor =
        [[UIColor blackColor] colorWithAlphaComponent:0.8];

        logView.textColor = UIColor.greenColor;
        logView.font = [UIFont systemFontOfSize:12];
        logView.editable = NO;

        logView.layer.cornerRadius = 8;
        logView.layer.masksToBounds = YES;

        [window addSubview:logView];
    });
}

void AppLog(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if(!logView) return;

        NSString *old = logView.text ?: @"";

        NSString *newText =
        [old stringByAppendingFormat:@"\n%@", msg];

        logView.text = newText;

        NSRange bottom =
        NSMakeRange(newText.length-1,1);

        [logView scrollRangeToVisible:bottom];
    });
}


#pragma mark - JSON处理

void RemoveKeyRecursive(id obj)
{
    if ([obj isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary *dict = (NSMutableDictionary *)obj;

        if (dict[REMOVE_FIELD])
        {
            [dict removeObjectForKey:REMOVE_FIELD];
            AppLog(@"remove isFiveVerif");
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

    if(!json || error)
        return data;

    RemoveKeyRecursive(json);

    NSData *newData =
    [NSJSONSerialization dataWithJSONObject:json
                                    options:0
                                      error:nil];

    return newData;
}


#pragma mark - NSURLProtocol

@implementation JsonHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;

    if ([url hasPrefix:@"http"])
    {
        AppLog([NSString stringWithFormat:@"REQ %@", url]);
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

    __unsafe_unretained typeof(self) weakSelf = self;

    self.task =
    [session dataTaskWithRequest:self.request
               completionHandler:^(NSData *data,
                                   NSURLResponse *response,
                                   NSError *error)
    {

        if(data)
            data = ProcessJSON(data);

        [weakSelf.client URLProtocol:weakSelf
                 didReceiveResponse:response
                 cacheStoragePolicy:NSURLCacheStorageNotAllowed];

        if(data)
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


#pragma mark - 注入Session

%hook NSURLSessionConfiguration

- (void)setProtocolClasses:(NSArray *)protocolClasses
{
    NSMutableArray *arr = [protocolClasses mutableCopy];

    if(![arr containsObject:[JsonHookProtocol class]])
    {
        [arr insertObject:[JsonHookProtocol class] atIndex:0];
    }

    %orig(arr);
}

%end


#pragma mark - 打印请求

%hook NSURLSessionTask

- (void)resume
{
    NSString *url =
    self.currentRequest.URL.absoluteString;

    AppLog([NSString stringWithFormat:@"TASK %@",url]);

    %orig;
}

%end


#pragma mark - 初始化

%ctor
{
    NSLog(@"[JSON HOOK] Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{

        InitLogWindow();
        AppLog(@"JsonHook Loaded");
    });

    [NSURLProtocol registerClass:[JsonHookProtocol class]];
}