#import "CDVFileTransfer+Cache.h"
#import <Cordova/CDV.h>
#import "VIMediaCache.h"
#import "VIMediaDownloader.h"
#import "VIMediaCacheWorker.h"

static NSString *kCacheScheme = @"__VIMediaCache___:";

@interface CDVFileTransferDelegateOb: CDVFileTransferDelegate<VIMediaDownloaderDelegate>

@end
@implementation CDVFileTransferDelegateOb
- (void)updateProgress:(VICacheConfiguration*)configuration{
   
    self.bytesTransfered = configuration.downloadedBytes;
    self.bytesExpected = [configuration contentLength];
     NSLog(@"download %d",self.bytesTransfered);
    [self updateProgress];
}
- (void)mediaDownloader:(VIMediaDownloader *)downloader didReceiveResponse:(NSURLResponse *)response{
    // 输出返回的状态码，请求成功的话返回为200
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    NSInteger responseStatusCode = [httpResponse statusCode];
    NSLog(@"%ld", (long)responseStatusCode);
    self.responseCode = responseStatusCode;
}
- (void)mediaDownloader:(VIMediaDownloader *)downloader didFinishedWithError:(NSError *)error {
    CDVPluginResult* result = nil;
    
    // remove connection for activeTransfers
    @synchronized (self.command.activeTransfers) {
        [self.command.activeTransfers removeObjectForKey:self.objectId];
        // remove background id task in case our upload was done in the background
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskID];
        self.backgroundTaskID = UIBackgroundTaskInvalid;
    }
    
    if (error.code == NSURLErrorCancelled) {
        CDVFileTransferError errorCode = CONNECTION_ABORTED;
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self.command createFileTransferError:errorCode AndSource:nil AndTarget:nil AndHttpStatus:self.responseCode AndBody:nil]];
        [self.command.commandDelegate sendPluginResult:result callbackId:self.callbackId];
        return;
    }
    
    if (!error) {
      //  [self.request finishLoading];
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self.filePlugin makeEntryForURL:self.targetURL]];
    } else {
       // [self.request finishLoadingWithError:error];
        
        CDVFileTransferError errorCode = CONNECTION_ERR;
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self.command createFileTransferError:errorCode AndSource:nil AndTarget:nil AndHttpStatus:self.responseCode AndBody:nil]];
    }
    [self.command.commandDelegate sendPluginResult:result callbackId:self.callbackId];
    /*
    NSString* body = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self.command createFileTransferError:CONNECTION_ERR AndSource:source AndTarget:target AndHttpStatus:self.responseCode AndBody:body]];
    
    NSLog(@"File Transfer Error: %@", [error localizedDescription]);
    
   // [self cancelTransfer:connection];
    [self.command.commandDelegate sendPluginResult:result callbackId:callbackId];
     */
}

@end

@implementation CDVFileTransfer (Cache)


- (void)download:(CDVInvokedUrlCommand*)command
{
    NSString* source = [command argumentAtIndex:0];
    NSString* target = [command argumentAtIndex:1];
    BOOL trustAllHosts = [[command argumentAtIndex:2 withDefault:[NSNumber numberWithBool:NO]] boolValue]; // allow self-signed certs
    NSString* objectId = [command argumentAtIndex:3];
    NSDictionary* headers = [command argumentAtIndex:4 withDefault:nil];
    
    CDVPluginResult* result = nil;
    CDVFileTransferError errorCode = 0;
    
    NSURL* targetURL;
    
    if ([target hasPrefix:@"/"]) {
        /* Backwards-compatibility:
         * Check here to see if it looks like the user passed in a raw filesystem path. (Perhaps they had the path saved, and were previously using it with the old version of File). If so, normalize it by removing empty path segments, and check with File to see if any of the installed filesystems will handle it. If so, then we will end up with a filesystem url to use for the remainder of this operation.
         */
        target = [target stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
        targetURL = [[self.commandDelegate getCommandInstance:@"File"] fileSystemURLforLocalPath:target].url;
    } else {
        targetURL = [NSURL URLWithString:target];
        
        if (targetURL == nil) {
            NSString* targetUrlTextEscaped = [target stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            if (targetUrlTextEscaped) {
                targetURL = [NSURL URLWithString:targetUrlTextEscaped];
            }
        }
    }
    
    NSURL* sourceURL = [NSURL URLWithString:source];

    
    if (!sourceURL) {
        errorCode = INVALID_URL_ERR;
        NSLog(@"File Transfer Error: Invalid server URL %@", source);
    } else if (!targetURL) {
        errorCode = INVALID_URL_ERR;
        NSLog(@"File Tranfer Error: Invalid target URL %@", target);
    } else if (![targetURL isFileURL]) {
        CDVFilesystemURL *fsURL = [CDVFilesystemURL fileSystemURLWithString:target];
        if (!fsURL) {
            errorCode = FILE_NOT_FOUND_ERR;
            NSLog(@"File Transfer Error: Invalid file path or URL %@", target);
        }
    }
    
    if (errorCode > 0) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[self createFileTransferError:errorCode AndSource:source AndTarget:target]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    CDVFileTransferDelegateOb* delegate = [[CDVFileTransferDelegateOb alloc] init];
    delegate.command = self;
    delegate.direction = CDV_TRANSFER_DOWNLOAD;
    delegate.callbackId = command.callbackId;
    delegate.objectId = objectId;
    delegate.source = source;
    delegate.target = [targetURL absoluteString];
    delegate.targetURL = targetURL;
    delegate.trustAllHosts = trustAllHosts;
    delegate.filePlugin = [self.commandDelegate getCommandInstance:@"File"];
    
    @synchronized (self.activeTransfers) {
        self.activeTransfers[delegate.objectId] = delegate;
    }
    
    if ([sourceURL.absoluteString hasPrefix:kCacheScheme]) {
        NSURL *originURL = nil;
        NSString *originStr = [sourceURL absoluteString];
        originStr = [originStr stringByReplacingOccurrencesOfString:kCacheScheme withString:@""];
        originURL = [NSURL URLWithString:originStr];
        sourceURL = originURL;
        
        VIMediaCacheWorker *_cacheWorker = [[VIMediaCacheWorker alloc] initWithURL:sourceURL];
        VIMediaDownloader *downloader = [[VIMediaDownloader alloc] initWithURL:sourceURL cacheWorker:_cacheWorker];
        downloader.delegate = delegate;
        delegate.backgroundTaskID=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [downloader cancel];
            NSLog(@"end=============");
            [[UIApplication sharedApplication] endBackgroundTask:delegate.backgroundTaskID];
            delegate.backgroundTaskID = UIBackgroundTaskInvalid;
        }];
        dispatch_async(
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, (unsigned long)NULL),
                       ^(void) {
                           [downloader downloadFromStartToEnd];
                       }
                       );
    }else{
        NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:sourceURL];
        [self applyRequestHeaders:headers toRequest:req];
        delegate.backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [delegate cancelTransfer:delegate.connection];
        }];
        
        delegate.connection = [[NSURLConnection alloc] initWithRequest:req delegate:delegate startImmediately:NO];
        
        if (self.queue == nil) {
            self.queue = [[NSOperationQueue alloc] init];
        }
        [delegate.connection setDelegateQueue:self.queue];
        

        // Downloads can take time
        // sending this to a new thread calling the download_async method
        dispatch_async(
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, (unsigned long)NULL),
                       ^(void) { [delegate.connection start];}
                       );
    }

}



@end
