#import <Foundation/Foundation.h>

#define REMOVE_KEY @"isFiveVerif"

static void RemoveKey(id obj)
{
    if([obj isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary *dict = obj;

        if(dict[REMOVE_KEY])
        {
            [dict removeObjectForKey:REMOVE_KEY];
            NSLog(@"Removed %@", REMOVE_KEY);
        }

        for(id key in dict)
        {
            RemoveKey(dict[key]);
        }
    }
    else if([obj isKindOfClass:[NSArray class]])
    {
        for(id item in obj)
        {
            RemoveKey(item);
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

    if(json && [json isKindOfClass:[NSDictionary class]])
    {
        NSMutableDictionary *mutable = [json mutableCopy];

        // Ensure RemoveKey is called on a valid mutable dictionary
        RemoveKey(mutable);

        newData = [NSJSONSerialization dataWithJSONObject:mutable options:0 error:nil];
    }

    %orig(session, task, newData);
}

%end