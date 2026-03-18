#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define HOOK_FIELD @"isFiveVerif"
#define HOOK_VALUE @"0"

@interface JsonHookProtocol : NSURLProtocol
@property(nonatomic,strong) NSURLSessionDataTask *task;
@end

#pragma mark - 屏幕提示

void ShowMsg(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window)
            window = [UIApplication sharedApplication].windows.firstObject;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20,120,320,40)];

        label.text = msg;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        label.layer.cornerRadius = 8;
        label.layer.masksToBounds = YES;

        [window addSubview:label];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            [label removeFromSuperview];
        });
    });
}

#pragma mark - JSON替换

NSData *ReplaceJSON(NSData *data)
{
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(!str) return data;

    if([str containsString:HOOK_FIELD])
    {
        NSString *pattern1 = [NSString stringWithFormat:@"\"%@\":1",HOOK_FIELD];
        NSString *pattern2 = [NSString stringWithFormat:@"\"%@\":true",HOOK_FIELD];

        NSString *replace = [NSString stringWithFormat:@"\"%@\":\"%@\"",HOOK_FIELD,HOOK_VALUE];

        str = [str stringByReplacingOccurrencesOfString:pattern1 withString:replace];
        str = [str stringByReplacingOccurrencesOfString:pattern2 withString:replace];

        NSLog(@"[JSON HOOK] %@ -> %@",HOOK_FIELD,HOOK_VALUE);
        ShowMsg(@"JSON Hook Triggered");

        return [str dataUsingEncoding:NSUTF8StringEncoding];
    }

    return data;
}

@implementation JsonHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *url = request.URL.absoluteString;

    if([url hasPrefix:@"http"])
    {
        NSLog(@"[HTTP] %@",url);
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

        if(data)
        {
            data = ReplaceJSON(data);
        }

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
    NSMutableArray *array = [protocolClasses mutableCopy];

    if(![array containsObject:[JsonHookProtocol class]])
    {
        [array insertObject:[JsonHookProtocol class] atIndex:0];
    }

    %orig(array);
}

%end


#pragma mark - 打印所有请求

%hook NSURLSessionTask

- (void)resume
{
    NSLog(@"[REQUEST] %@",self.currentRequest.URL);
    %orig;
}

%end


#pragma mark - 初始化

%ctor
{
    NSLog(@"[JSON HOOK] Loaded");

    [NSURLProtocol registerClass:[JsonHookProtocol class]];
}