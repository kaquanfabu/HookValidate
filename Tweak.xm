#import#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define REMOVE_FIELD @"isFiveVerif"

@interface JsonHookProtocol : NSURLProtocol
@property(nonatomic,strong) NSURLSessionDataTask *task;
@end

static UITextView *logView = nil;
static UIButton *clearBtn = nil;
static UIButton *toggleBtn = nil;
static UIView *dragHandle = nil;
static BOOL isLogVisible = YES;
static BOOL isHookEnabled = YES;

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

#pragma mark - 可拖动的UI日志

void InitLogWindow()
{
    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = GetKeyWindow();

        if (!window) return;

        // 创建背景面板（可拖动区域）
        UIView *panelView = [[UIView alloc] initWithFrame:CGRectMake(10, 120, 355, 300)];
        panelView.backgroundColor = [UIColor clearColor];
        panelView.tag = 98765; // 便于查找
        panelView.userInteractionEnabled = YES;
        
        // 添加拖动把手
        dragHandle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 355, 30)];
        dragHandle.backgroundColor = [[UIColor darkGrayColor] colorWithAlphaComponent:0.9];
        dragHandle.layer.cornerRadius = 8;
        dragHandle.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        dragHandle.userInteractionEnabled = YES;
        [panelView addSubview:dragHandle];
        
        // 添加标题标签
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 200, 20)];
        titleLabel.text = @"📋 JSON Hook Log";
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [dragHandle addSubview:titleLabel];
        
        // 添加状态指示器
        UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(310, 5, 40, 20)];
        statusLabel.text = @"●";
        statusLabel.textColor = [UIColor greenColor];
        statusLabel.font = [UIFont systemFontOfSize:20];
        statusLabel.tag = 98766;
        [dragHandle addSubview:statusLabel];
        
        // 日志文本框
        logView = [[UITextView alloc] initWithFrame:CGRectMake(0, 30, 355, 240)];
        logView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        logView.textColor = UIColor.greenColor;
        logView.font = [UIFont systemFontOfSize:12];
        logView.editable = NO;
        logView.userInteractionEnabled = YES;
        [panelView addSubview:logView];
        
        // 按钮面板
        UIView *buttonPanel = [[UIView alloc] initWithFrame:CGRectMake(0, 270, 355, 30)];
        buttonPanel.backgroundColor = [[UIColor darkGrayColor] colorWithAlphaComponent:0.9];
        buttonPanel.layer.cornerRadius = 8;
        buttonPanel.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        [panelView addSubview:buttonPanel];
        
        // 清除按钮
        clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        clearBtn.frame = CGRectMake(10, 5, 60, 20);
        [clearBtn setTitle:@"清除" forState:UIControlStateNormal];
        [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        clearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        clearBtn.backgroundColor = [UIColor grayColor];
        clearBtn.layer.cornerRadius = 3;
        [clearBtn addTarget:nil action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];
        [buttonPanel addSubview:clearBtn];
        
        // 隐藏/显示按钮
        toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        toggleBtn.frame = CGRectMake(80, 5, 60, 20);
        [toggleBtn setTitle:@"隐藏" forState:UIControlStateNormal];
        [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        toggleBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        toggleBtn.backgroundColor = [UIColor grayColor];
        toggleBtn.layer.cornerRadius = 3;
        [toggleBtn addTarget:nil action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];
        [buttonPanel addSubview:toggleBtn];
        
        // Hook开关按钮
        UIButton *hookToggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        hookToggleBtn.frame = CGRectMake(150, 5, 60, 20);
        [hookToggleBtn setTitle:@"Hook开" forState:UIControlStateNormal];
        [hookToggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookToggleBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        hookToggleBtn.backgroundColor = [UIColor greenColor];
        hookToggleBtn.layer.cornerRadius = 3;
        hookToggleBtn.tag = 98767;
        [hookToggleBtn addTarget:nil action:@selector(toggleHook) forControlEvents:UIControlEventTouchUpInside];
        [buttonPanel addSubview:hookToggleBtn];
        
        // 添加拖动手势
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(dragLogPanel:)];
        [dragHandle addGestureRecognizer:panGesture];
        
        [window addSubview:panelView];
        
        // 保存原始位置
        objc_setAssociatedObject(panelView, "originalPosition", [NSValue valueWithCGPoint:panelView.frame.origin], OBJC_ASSOCIATION_RETAIN);
    });
}

#pragma mark - UI控制函数

void UpdateHookButtonState()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        UIButton *hookBtn = [window viewWithTag:98767];
        if (hookBtn) {
            [hookBtn setTitle:isHookEnabled ? @"Hook开" : @"Hook关" forState:UIControlStateNormal];
            hookBtn.backgroundColor = isHookEnabled ? [UIColor greenColor] : [UIColor redColor];
        }
        
        UILabel *statusLabel = [window viewWithTag:98766];
        if (statusLabel) {
            statusLabel.textColor = isHookEnabled ? [UIColor greenColor] : [UIColor redColor];
        }
    });
}

void ClearLog()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        logView.text = @"";
        AppLog(@"📋 日志已清除");
    });
}

void ToggleLogVisibility()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        UIView *panel = [window viewWithTag:98765];
        
        isLogVisible = !isLogVisible;
        
        [UIView animateWithDuration:0.3 animations:^{
            if (isLogVisible) {
                panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 355, 300);
                [toggleBtn setTitle:@"隐藏" forState:UIControlStateNormal];
            } else {
                panel.frame = CGRectMake(panel.frame.origin.x, panel.frame.origin.y, 355, 30);
                [toggleBtn setTitle:@"显示" forState:UIControlStateNormal];
            }
        }];
    });
}

void ToggleHook()
{
    isHookEnabled = !isHookEnabled;
    UpdateHookButtonState();
    AppLog([NSString stringWithFormat:@"🔌 Hook %@", isHookEnabled ? @"已开启" : @"已关闭"]);
}

void DragLogPanel(UIPanGestureRecognizer *gesture)
{
    UIView *panel = gesture.view.superview;
    if (!panel) return;
    
    CGPoint translation = [gesture translationInView:panel.superview];
    CGPoint newCenter = CGPointMake(panel.center.x + translation.x,
                                    panel.center.y + translation.y);
    
    // 边界限制
    CGRect bounds = panel.superview.bounds;
    newCenter.x = MAX(panel.frame.size.width/2, MIN(newCenter.x, bounds.size.width - panel.frame.size.width/2));
    newCenter.y = MAX(panel.frame.size.height/2, MIN(newCenter.y, bounds.size.height - panel.frame.size.height/2));
    
    panel.center = newCenter;
    [gesture setTranslation:CGPointZero inView:panel.superview];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        // 保存位置
        objc_setAssociatedObject(panel, "lastPosition", [NSValue valueWithCGPoint:panel.frame.origin], OBJC_ASSOCIATION_RETAIN);
    }
}

void AppLog(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if(!logView || !isLogVisible) return;

        NSString *old = logView.text ?: @"";
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *time = [formatter stringFromDate:[NSDate date]];

        // 根据消息类型添加emoji
        NSString *emojiMsg = msg;
        if ([msg containsString:@"REQ"] || [msg containsString:@"请求"]) {
            emojiMsg = [@"⬆️ " stringByAppendingString:msg];
        } else if ([msg containsString:@"RES"] || [msg containsString:@"响应"]) {
            emojiMsg = [@"⬇️ " stringByAppendingString:msg];
        } else if ([msg containsString:@"Modified"] || [msg containsString:@"修改"]) {
            emojiMsg = [@"✏️ " stringByAppendingString:msg];
        } else if ([msg containsString:@"Error"] || [msg containsString:@"错误"]) {
            emojiMsg = [@"❌ " stringByAppendingString:msg];
        }

        NSString *newText =
        [old stringByAppendingFormat:@"\n[%@] %@", time, emojiMsg];

        // 限制日志行数
        NSArray *lines = [newText componentsSeparatedByString:@"\n"];
        if (lines.count > 200) {
            NSArray *lastLines = [lines subarrayWithRange:NSMakeRange(lines.count - 200, 200)];
            newText = [lastLines componentsJoinedByString:@"\n"];
        }

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
            AppLog([NSString stringWithFormat:@"✅ 移除字段: %@", REMOVE_FIELD]);
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
    if (!isHookEnabled) return data;
    
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

    return newData ?: data;
}

#pragma mark - NSURLProtocol 实现

@implementation JsonHookProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if (!isHookEnabled) return NO;
    
    NSString *url = request.URL.absoluteString;

    if (![url hasPrefix:@"http"])
        return NO;

    if ([NSURLProtocol propertyForKey:@"JsonHooked" inRequest:request])
        return NO;

    NSLog(@"[JsonHook] Intercepting: %@", url);
    AppLog([NSString stringWithFormat:@"🌐 请求: %@", url]);

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
    
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 60;

    NSURLSession *session =
    [NSURLSession sessionWithConfiguration:config
                                  delegate:nil
                             delegateQueue:nil];

    __weak typeof(self) weakSelf = self;

    self.task =
    [session dataTaskWithRequest:newReq
               completionHandler:^(NSData *data,
                                   NSURLResponse *response,
                                   NSError *error)
    {
        if (error) {
            AppLog([NSString stringWithFormat:@"❌ 请求错误: %@", error.localizedDescription]);
            [weakSelf.client URLProtocol:weakSelf didFailWithError:error];
            return;
        }

        NSData *modifiedData = data;
        NSString *contentType = response.MIMEType;
        
        // 只处理JSON响应
        if ([contentType containsString:@"application/json"] || 
            [contentType containsString:@"text/json"]) {
            modifiedData = ProcessJSON(data);
            
            if (modifiedData != data) {
                AppLog(@"✅ 已修改JSON响应");
            }
        }

        [weakSelf.client URLProtocol:weakSelf
                  didReceiveResponse:response
                  cacheStoragePolicy:NSURLCacheStorageNotAllowed];

        if (modifiedData) {
            [weakSelf.client URLProtocol:weakSelf didLoadData:modifiedData];
        }

        [weakSelf.client URLProtocolDidFinishLoading:weakSelf];
    }];

    [self.task resume];
}

- (void)stopLoading
{
    [self.task cancel];
}

@end

#pragma mark - Alamofire Hook

@interface NSObject (AlamofireHook)
+ (void)swizzleAlamofireMethods;
@end

@implementation NSObject (AlamofireHook)

+ (void)swizzleAlamofireMethods
{
    // 查找Alamofire的SessionDelegate类
    Class sessionDelegateClass = NSClassFromString(@"Alamofire.SessionDelegate");
    if (!sessionDelegateClass) {
        sessionDelegateClass = NSClassFromString(@"_TtC9Alamofire14SessionDelegate");
    }
    
    if (sessionDelegateClass) {
        AppLog(@"✅ 找到Alamofire.SessionDelegate");
        
        // Swizzle URLSession:dataTask:didReceiveData: 方法
        SEL originalSelector = @selector(URLSession:dataTask:didReceiveData:);
        SEL swizzledSelector = @selector(hook_URLSession:dataTask:didReceiveData:);
        
        Method originalMethod = class_getInstanceMethod(sessionDelegateClass, originalSelector);
        Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);
        
        if (originalMethod && swizzledMethod) {
            method_exchangeImplementations(originalMethod, swizzledMethod);
            AppLog(@"✅ 已Swizzle SessionDelegate方法");
        }
    } else {
        AppLog(@"ℹ️ 未找到Alamofire.SessionDelegate");
    }
    
    // Hook URLSessionConfiguration 创建方法
    Class configClass = [NSURLSessionConfiguration class];
    
    SEL defaultConfigSelector = @selector(defaultSessionConfiguration);
    SEL swizzledDefaultSelector = @selector(hook_defaultSessionConfiguration);
    
    Method defaultConfigMethod = class_getClassMethod(configClass, defaultConfigSelector);
    Method swizzledDefaultMethod = class_getClassMethod([self class], swizzledDefaultSelector);
    
    if (defaultConfigMethod && swizzledDefaultMethod) {
        method_exchangeImplementations(defaultConfigMethod, swizzledDefaultMethod);
        AppLog(@"✅ 已Swizzle defaultSessionConfiguration");
    }
}

#pragma mark - Hook Methods

- (void)hook_URLSession:(NSURLSession *)session 
               dataTask:(NSURLSessionDataTask *)dataTask 
         didReceiveData:(NSData *)data
{
    if (!isHookEnabled) {
        [self hook_URLSession:session dataTask:dataTask didReceiveData:data];
        return;
    }
    
    NSString *url = dataTask.originalRequest.URL.absoluteString;
    AppLog([NSString stringWithFormat:@"📦 Alamofire数据: %@", url]);
    
    // 处理数据
    NSData *modifiedData = ProcessJSON(data);
    
    if (modifiedData != data) {
        AppLog(@"✅ 已修改Alamofire响应");
    }
    
    // 调用原始方法
    [self hook_URLSession:session dataTask:dataTask didReceiveData:modifiedData];
}

+ (NSURLSessionConfiguration *)hook_defaultSessionConfiguration
{
    NSURLSessionConfiguration *config = [self hook_defaultSessionConfiguration];
    
    if (isHookEnabled) {
        // 注入我们的Protocol
        NSMutableArray *protocols = [config.protocolClasses mutableCopy];
        if (!protocols) {
            protocols = [NSMutableArray array];
        }
        
        if (![protocols containsObject:[JsonHookProtocol class]]) {
            [protocols insertObject:[JsonHookProtocol class] atIndex:0];
            config.protocolClasses = protocols;
            AppLog(@"✅ 已注入Protocol到默认配置");
        }
    }
    
    return config;
}

@end

#pragma mark - 更底层的Hook

@interface NSURLProtocol (ForceLoad)
+ (void)forceLoad;
@end

@implementation NSURLProtocol (ForceLoad)

+ (void)forceLoad
{
    Class cls = [JsonHookProtocol class];
    
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    
    for (int i = 0; i < numClasses; i++) {
        Class superClass = classes[i];
        if (class_getSuperclass(superClass) == [NSURLProtocol class]) {
            [NSURLProtocol registerClass:superClass];
        }
    }
    
    free(classes);
}

@end

#pragma mark - UIResponder Category for Actions

@interface UIResponder (LogActions)
- (void)clearLog;
- (void)toggleLog;
- (void)toggleHook;
- (void)dragLogPanel:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIResponder (LogActions)

- (void)clearLog
{
    ClearLog();
}

- (void)toggleLog
{
    ToggleLogVisibility();
}

- (void)toggleHook
{
    ToggleHook();
}

- (void)dragLogPanel:(UIPanGestureRecognizer *)gesture
{
    DragLogPanel(gesture);
}

@end

#pragma mark - Tweak 初始化

%ctor
{
    NSLog(@"[JsonHook] ========================");
    NSLog(@"[JsonHook] 加载中...");
    NSLog(@"[JsonHook] ========================");
    
    // 1. 注册NSURLProtocol
    [NSURLProtocol registerClass:[JsonHookProtocol class]];
    NSLog(@"[JsonHook] NSURLProtocol已注册");
    
    // 2. 强制重新注册所有Protocol
    [NSURLProtocol forceLoad];
    
    // 3. Swizzle Alamofire方法
    [NSObject swizzleAlamofireMethods];
    
    // 4. Hook所有可能的configuration
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSMutableArray *protocols = [config.protocolClasses mutableCopy];
        if (![protocols containsObject:[JsonHookProtocol class]]) {
            [protocols insertObject:[JsonHookProtocol class] atIndex:0];
            config.protocolClasses = protocols;
            NSLog(@"[JsonHook] 已注入到主配置");
        }
    });
    
    // 5. 延迟初始化UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        
        InitLogWindow();
        UpdateHookButtonState();
        AppLog(@"🚀 JSON Hook 已加载");
        AppLog(@"🎯 目标字段: %@", REMOVE_FIELD);
        AppLog(@"💡 拖动上方把手可移动窗口");
        
        // 打印调试信息
        Class alamofireClass = NSClassFromString(@"Alamofire.Session");
        if (alamofireClass) {
            AppLog(@"✅ Alamofire.Session 可用");
        }
    });
}