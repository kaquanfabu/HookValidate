#import <Foundation/Foundation.h>

%hook SessionDelegate

// Intercept the response data
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    // Check if the URL matches the one we want to intercept
    if ([task.currentRequest.URL.absoluteString containsString:@"wap.jx.10086.cn/nwgt/web/api/v1/menu/validate"]) {
        
        // Convert the NSData response to a string
        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        // Replace "validateItem" array with [NSNull null]
        dataString = [dataString stringByReplacingOccurrencesOfString:@"\"validateItem\": \"0,1,2,3,4\""
                                                           withString:@"\"validateItem\": null"];
        
        // Convert the modified string back to NSData
        data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    // Pass the modified data to the original method
    %orig(session, task, data);
}

%end

// Initialize the hook for SessionDelegate
%ctor {
    %init(SessionDelegate = objc_getClass("Alamofire.SessionDelegate"));
}