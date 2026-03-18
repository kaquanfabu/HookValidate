#import <Foundation/Foundation.h>

static NSMutableDictionary *taskBuffer;

%hook NSObject

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
   didReceiveData:(NSData *)data
{
    if (!taskBuffer)
        taskBuffer = [NSMutableDictionary dictionary];

    NSString *url = dataTask.currentRequest.URL.absoluteString;

    if ([url containsString:@"/nwgt/web/api/v1/menu/validate"])
    {
        NSNumber *taskId = @(dataTask.taskIdentifier);

        NSMutableData *buf = taskBuffer[taskId];
        if (!buf)
        {
            buf = [NSMutableData data];
            taskBuffer[taskId] = buf;
        }

        [buf appendData:data];

        // 不把真实数据继续往上送
        return;
    }

    %orig;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    NSString *url = task.currentRequest.URL.absoluteString;

    if ([url containsString:@"/nwgt/web/api/v1/menu/validate"])
    {
        NSString *fakeJson =
        @"{"
        "\"sing\":null,"
        "\"data\":null,"
        "\"code\":0,"
        "\"message\":\"请求成功\","
        "\"success\":true,"
        "\"skey\":null,"
        "\"timestamp\":1773846248358"
        "}";

        NSData *fakeData = [fakeJson dataUsingEncoding:NSUTF8StringEncoding];

        NSLog(@"[HOOK] validate api replaced");

        // 直接伪造回调
        if ([self respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)])
        {
            ((void (*)(id, SEL, NSURLSession*, NSURLSessionDataTask*, NSData*))
            objc_msgSend)(self,
            @selector(URLSession:dataTask:didReceiveData:),
            session,
            (NSURLSessionDataTask *)task,
            fakeData);
        }
    }

    %orig;
}

%end