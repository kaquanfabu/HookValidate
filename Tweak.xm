#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define REMOVE_FIELD @"isFiveVerif"

@interface JsonHookProtocol : NSURLProtocol
@property(nonatomic,strong) NSURLSessionDataTask *task;
@end

static UITextView *logView = nil;

#pragma mark - 获取Window (兼容iOS9-17)

UIWindow *GetKeyWindow()
{
    UIWindow *window = nil;

    if (@available(iOS 13.0, *))
    {
        NSSet *scenes = [UIApplication sharedApplication].connectedScenes;

        for (UIScene *scene in scenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]])
            {
                UIWindowScene *windowScene = (UIWindowScene *)scene;

                for (UIWindow *w in windowScene.windows)
                {
                    if (w.isKeyWindow)
                    {
                        window = w;
                        break;
                    }
                }
            }

            if (window) break;
        }
    }
    else
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        window = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }

    return window;
}

#pragma mark - UI日志

void InitLogWindow()
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = GetKeyWindow();

        if (!window) return;

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

    if (![url hasPrefix:@"http"])
        return NO;

    if ([NSURLProtocol propertyForKey:@"JsonHooked" inRequest:request])
        return NO;

    AppLog([NSString stringWithFormat:@"REQ %@", url]);

    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSMutableURLRequest *newReq =
    [self.request mutableCopy];

    [NSURLProtocol setProperty:@YES
                        forKey:@"JsonHooked"
                     inRequest:newReq];

    NSURLSessionConfiguration *config =
    [NSURLSessionConfiguration defaultSessionConfiguration];

    NSURLSession *session =
    [NSURLSession sessionWithConfiguration:config];

    __unsafe_unretained typeof(self) weakSelf = self;

    self.task =
    [session dataTaskWithRequest:newReq
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

#pragma mark - 请求日志

%hook NSURLSessionTask

- (void)resume
{
    NSString *url =
    self.currentRequest.URL.absoluteString;

    AppLog([NSString stringWithFormat:@"TASK %@", url]);

    %orig;
}

%end

#pragma mark - 初始化

%ctor
{
    NSLog(@"[JsonHook] Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{

        InitLogWindow();
        AppLog(@"JsonHook Loaded");
    });

    [NSURLProtocol registerClass:[JsonHookProtocol class]];
}