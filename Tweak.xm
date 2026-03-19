#import <Foundation/Foundation.h>

#define REMOVE_KEY @"isFiveVerif"

// 将 RemoveKey 移动到实例方法中，避免作用域问题
- (void)RemoveKey:(id)obj
{
    if([obj isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary *dict = obj;

        if(dict[REMOVE_KEY])
        {
            [dict removeObjectForKey:REMOVE_KEY];
            NSLog(@"已移除 %@", REMOVE_KEY);
        }

        for(id key in dict)
        {
            [self RemoveKey:dict[key]];
        }
    }
    else if([obj isKindOfClass:[NSArray class]])
    {
        for(id item in obj)
        {
            [self RemoveKey:item];
        }
    }
}

%hook NSObject

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data
{
    NSData *newData = data;

    id json = [NSJSONSerialization JSONObjectWithData:data options:1 error:nil];

    // 确保 json 实际上是一个字典
    if (json && [json isKindOfClass:[NSDictionary class]])
    {
        NSLog(@"接收到的 JSON: %@", json); // 输出接收到的 JSON
        NSMutableDictionary *mutable = [json mutableCopy];

        // 确保 RemoveKey 正确调用
        [self RemoveKey:mutable];

        newData = [NSJSONSerialization dataWithJSONObject:mutable options:0 error:nil];
    }
    else
    {
        NSLog(@"错误：接收到的 JSON 不是字典类型: %@", json);
    }

    %orig(session, task, newData);
}

%end