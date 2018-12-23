#import "StreamingMedia.h"
#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "学英语听新闻-Swift.h"
#import "CDVFile.h"
#import "HWWeakTimer.h"
#import "VIMediaCache.h"
#import "VIMediaDownloader.h"
#import "VIMediaCacheWorker.h"
#define DOCUMENTS_SCHEME_PREFIX @"documents://"
#define HTTP_SCHEME_PREFIX @"http://"
#define HTTPS_SCHEME_PREFIX @"https://"
#define CDVFILE_PREFIX @"cdvfile://"
//#import "JHRotatoUtil.h"
@interface StreamingMedia()
	- (void)parseOptions:(NSDictionary *) options type:(NSString *) type;
	- (void)play:(CDVInvokedUrlCommand *) command type:(NSString *) type;
	- (void)setBackgroundColor:(NSString *)color;
	- (void)setImage:(NSString*)imagePath withScaleType:(NSString*)imageScaleType;
	- (UIImage*)getImage: (NSString *)imageName;
- (void)startPlayer:(NSString*)uri withSrt:(NSString*) srt;
	- (void)moviePlayBackDidFinish:(NSNotification*)notification;
	- (void)cleanup;
@property UIInterfaceOrientation orientation;
@property (nonatomic, assign) BOOL             isUserPlay;
@property (nonatomic, weak) NSTimer *timer;

@property (nonatomic, strong) UIScreen *extScreen;
@property (nonatomic, strong) UIWindow *extWindow;
@property (nonatomic, strong) NSArray *availableModes;
@property (nonatomic, strong) VIResourceLoaderManager *resourceLoaderManager;
@end

@implementation StreamingMedia {
    NSString* callbackId;
	AVPlayerViewController *moviePlayer;
    UIView *superView;
	BOOL shouldAutoClose;
	UIColor *backgroundColor;
	UIImageView *imageView;
    BOOL initFullscreen;
}
NSString * const TYPE_VIDEO = @"VIDEO";
NSString * const TYPE_AUDIO = @"AUDIO";
NSString * const DEFAULT_IMAGE_SCALE = @"center";

static NSString * const VIDEO_CONTROLLER_CLASS_NAME_IOS7 = @"MPInlineVideoFullscreenViewController";
static NSString * const VIDEO_CONTROLLER_CLASS_NAME_IOS8 = @"AVFullScreenViewController";

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window{
    if ([[window.rootViewController presentedViewController] isKindOfClass:NSClassFromString(VIDEO_CONTROLLER_CLASS_NAME_IOS7)] ||
        [[window.rootViewController presentedViewController] isKindOfClass:NSClassFromString(VIDEO_CONTROLLER_CLASS_NAME_IOS8)])
    {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    else {
        NSNumber *value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
        [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
        
        [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
        return UIInterfaceOrientationMaskPortrait;}
}

-(void)parseOptions:(NSDictionary *)options type:(NSString *) type {
	// Common options
	if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"shouldAutoClose"]) {
		shouldAutoClose = [[options objectForKey:@"shouldAutoClose"] boolValue];
	} else {
		shouldAutoClose = YES;
	}
	if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"bgColor"]) {
		[self setBackgroundColor:[options objectForKey:@"bgColor"]];    	} else {
		backgroundColor = [UIColor blackColor];
	}

    if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"initFullscreen"]) {
        initFullscreen = [[options objectForKey:@"initFullscreen"] boolValue];
    } else {
        initFullscreen = YES;
    }

	if ([type isEqualToString:TYPE_AUDIO]) {
		// bgImage
		// bgImageScale
		if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"bgImage"]) {
			NSString *imageScale = DEFAULT_IMAGE_SCALE;
			if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"bgImageScale"]) {
				imageScale = [options objectForKey:@"bgImageScale"];
			}
			[self setImage:[options objectForKey:@"bgImage"] withScaleType:imageScale];
		}
		// bgColor
		if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"bgColor"]) {
			NSLog(@"Found option for bgColor");
			[self setBackgroundColor:[options objectForKey:@"bgColor"]];
		} else {
			backgroundColor = [UIColor blackColor];
		}
	}
	// No specific options for video yet
    


}

-(void)play:(CDVInvokedUrlCommand *) command type:(NSString *) type {
	callbackId = command.callbackId;
    NSString *mediaUrl  = [command.arguments objectAtIndex:0];

	[self parseOptions:[command.arguments objectAtIndex:1] type:type];

    NSString *srtUrl  = nil;
    /*
    NSLog(@"%lu", [command.arguments count]);
    if([command.arguments count]>2){
        srtUrl =[command.arguments objectAtIndex:2];
    }
     */
   NSDictionary *options =  [command.arguments objectAtIndex:1];
    if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"srt"]) {
        srtUrl=[options objectForKey:@"srt"];
    }
    _isUserPlay  = YES;

    [self startPlayer:mediaUrl withSrt:srtUrl];
}

-(void)stop:(CDVInvokedUrlCommand *) command type:(NSString *) type {
    callbackId = command.callbackId;
    if (moviePlayer.player) {
        [moviePlayer.player pause];
        
    }
    _isUserPlay  = NO;

}

-(void)playVideo:(CDVInvokedUrlCommand *) command {
	[self play:command type:[NSString stringWithString:TYPE_VIDEO]];
}

-(void)playAudio:(CDVInvokedUrlCommand *) command {
	[self play:command type:[NSString stringWithString:TYPE_AUDIO]];
}

-(void)stopAudio:(CDVInvokedUrlCommand *) command {
    [self stop:command type:[NSString stringWithString:TYPE_AUDIO]];
}

-(void) setBackgroundColor:(NSString *)color {
	if ([color hasPrefix:@"#"]) {
		// HEX value
		unsigned rgbValue = 0;
		NSScanner *scanner = [NSScanner scannerWithString:color];
		[scanner setScanLocation:1]; // bypass '#' character
		[scanner scanHexInt:&rgbValue];
		backgroundColor = [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0];
	} else {
		// Color name
		NSString *selectorString = [[color lowercaseString] stringByAppendingString:@"Color"];
		SEL selector = NSSelectorFromString(selectorString);
		UIColor *colorObj = [UIColor blackColor];
		if ([UIColor respondsToSelector:selector]) {
			colorObj = [UIColor performSelector:selector];
		}
		backgroundColor = colorObj;
	}
}

-(UIImage*)getImage: (NSString *)imageName {
	UIImage *image = nil;
	if (imageName != (id)[NSNull null]) {
		if ([imageName hasPrefix:@"http"]) {
			// Web image
			image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageName]]];
		} else if ([imageName hasPrefix:@"www/"]) {
			// Asset image
			image = [UIImage imageNamed:imageName];
		} else if ([imageName hasPrefix:@"file://"]) {
			// Stored image
			image = [UIImage imageWithData:[NSData dataWithContentsOfFile:[[NSURL URLWithString:imageName] path]]];
		} else if ([imageName hasPrefix:@"data:"]) {
			// base64 encoded string
			NSURL *imageURL = [NSURL URLWithString:imageName];
			NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
			image = [UIImage imageWithData:imageData];
		} else {
			// explicit path
			image = [UIImage imageWithData:[NSData dataWithContentsOfFile:imageName]];
		}
	}
	return image;
}

- (void)orientationChanged:(NSNotification *)notification {
	if (imageView != nil) {
		// adjust imageView for rotation
		//imageView.bounds = moviePlayer.backgroundView.bounds;
		//imageView.frame = moviePlayer.backgroundView.frame;
	}
}

-(void)setImage:(NSString*)imagePath withScaleType:(NSString*)imageScaleType {
	imageView = [[UIImageView alloc] initWithFrame:self.viewController.view.bounds];
	if (imageScaleType == nil) {
		NSLog(@"imagescaletype was NIL");
		imageScaleType = DEFAULT_IMAGE_SCALE;
	}
	if ([imageScaleType isEqualToString:@"stretch"]){
		// Stretches image to fill all available background space, disregarding aspect ratio
		imageView.contentMode = UIViewContentModeScaleToFill;
		//moviePlayer.backgroundView.contentMode = UIViewContentModeScaleToFill;
	} else if ([imageScaleType isEqualToString:@"fit"]) {
		// Stretches image to fill all possible space while retaining aspect ratio
		imageView.contentMode = UIViewContentModeScaleAspectFit;
        //moviePlayer.backgroundView.contentMode = UIViewContentModeScaleAspectFit;
	} else {
		// Places image in the center of the screen
		imageView.contentMode = UIViewContentModeCenter;
		//moviePlayer.backgroundView.contentMode = UIViewContentModeCenter;
	}

	[imageView setImage:[self getImage:imagePath]];
}
- (NSURL*)urlForPlaying:(NSString*)resourcePath
{
    NSURL* resourceURL = nil;
    NSString* filePath = nil;
    
    // first try to find HTTP:// or Documents:// resources
    
    if ([resourcePath hasPrefix:HTTP_SCHEME_PREFIX] || [resourcePath hasPrefix:HTTPS_SCHEME_PREFIX]) {
        // if it is a http url, use it
        NSLog(@"Will use resource '%@' from the Internet.", resourcePath);
        resourceURL = [NSURL URLWithString:resourcePath];
    } else if ([resourcePath hasPrefix:DOCUMENTS_SCHEME_PREFIX]) {
        NSString* docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        filePath = [resourcePath stringByReplacingOccurrencesOfString:DOCUMENTS_SCHEME_PREFIX withString:[NSString stringWithFormat:@"%@/", docsPath]];
        NSLog(@"Will use resource '%@' from the documents folder with path = %@", resourcePath, filePath);
    } else if ([resourcePath hasPrefix:CDVFILE_PREFIX]) {
        CDVFile *filePlugin = [self.commandDelegate getCommandInstance:@"File"];
        CDVFilesystemURL *url = [CDVFilesystemURL fileSystemURLWithString:resourcePath];
        filePath = [filePlugin filesystemPathForURL:url];
        if (filePath == nil) {
            resourceURL = [NSURL URLWithString:resourcePath];
        }
    } else {
        // attempt to find file path in www directory or LocalFileSystem.TEMPORARY directory
        filePath = [self.commandDelegate pathForResource:resourcePath];
        if (filePath == nil) {
            // see if this exists in the documents/temp directory from a previous recording
            NSString* testPath = [NSString stringWithFormat:@"%@/%@", [NSTemporaryDirectory()stringByStandardizingPath], resourcePath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:testPath]) {
                // inefficient as existence will be checked again below but only way to determine if file exists from previous recording
                filePath = testPath;
                NSLog(@"Will attempt to use file resource from LocalFileSystem.TEMPORARY directory");
            } else {
                // attempt to use path provided
                filePath = resourcePath;
                NSLog(@"Will attempt to use file resource '%@'", filePath);
            }
        } else {
            NSLog(@"Found resource '%@' in the web folder.", filePath);
        }
    }
    // if the resourcePath resolved to a file path, check that file exists
    if (filePath != nil) {
        // create resourceURL
        resourceURL = [NSURL fileURLWithPath:filePath];
        // try to access file
        NSFileManager* fMgr = [NSFileManager defaultManager];
        if (![fMgr fileExistsAtPath:filePath]) {
            resourceURL = nil;
            NSLog(@"Unknown resource '%@'", resourcePath);
        }
    }
    
    return resourceURL;
}

#pragma mark - APP活动通知
/*- (void)appDidEnterBackground:(NSNotification *)note{
    //将要挂起，停止播放
   [moviePlayer.player play];
}*/
- (void)appDidEnterPlayground:(NSNotification *)note{
    //继续播放
    if (_isUserPlay) {
        [moviePlayer.player play];
    }
}
-(void)addSrt:(CDVInvokedUrlCommand *) command {
    callbackId = command.callbackId;
    
    [self parseOptions:[command.arguments objectAtIndex:1] type:TYPE_VIDEO];
    
    NSString *srtUrl  = nil;

    NSDictionary *options =  [command.arguments objectAtIndex:1];
    if (![options isKindOfClass:[NSNull class]] && [options objectForKey:@"srt"]) {
        srtUrl=[options objectForKey:@"srt"];
    }
    NSURL *subtitleUrl      =   [self urlForPlaying:srtUrl];

    if(subtitleUrl!=nil){
        [moviePlayer addSubtitlessWithFile:subtitleUrl];
    }
    
}
-(void)startPlayer:(NSString*)uri withSrt:(NSString*)srt {
    
	//NSURL *url             =  [NSURL URLWithString:uri];
    //
    NSURL *url             =   [self urlForPlaying:uri];
    VIResourceLoaderManager *resourceLoaderManager = [VIResourceLoaderManager new];
    self.resourceLoaderManager = resourceLoaderManager;
    AVPlayerItem *playerItem = [self.resourceLoaderManager playerItemWithURL:url];
    AVPlayer *movie = [AVPlayer playerWithPlayerItem:playerItem];
    //AVPlayer *movie        =  [AVPlayer playerWithURL:url];
    //BOOL isFirst = YES;
	//if(moviePlayer==nil)
        moviePlayer            =  [[AVPlayerViewController alloc] init];
    //else isFirst = NO;
    
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    

    [moviePlayer setPlayer:movie];
    [moviePlayer setShowsPlaybackControls:YES];
    if(@available(iOS 11.0, *)) { [moviePlayer setEntersFullScreenWhenPlaybackBegins:YES]; }

        //present modally so we get a close button
    

    [self.webView.superview addSubview:moviePlayer.view];
    [self.webView.superview bringSubviewToFront:self.webView];
    
    [self.viewController presentViewController:moviePlayer animated:YES completion:^(void){
        //let's start this bitch.
        [moviePlayer.player play];
        
        //airplay only can see when there is a air play
        //CGRect rect = [[UIScreen mainScreen] bounds];
        //CGSize size = rect.size;
        
        //MPVolumeView *volume = [[MPVolumeView alloc] initWithFrame:CGRectMake(0,100, 50, 50)];
        //volume.showsVolumeSlider = NO;
        //volume.showsRouteButton = TRUE;
        //[volume sizeToFit];
        //[moviePlayer.view addSubview:volume];
/*
        NSTimer *mtimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            NSLog(@"timer");
            if (moviePlayer.player.rate == 0 &&
                (moviePlayer.isBeingDismissed || moviePlayer.nextResponder == nil)) {
                // Handle user Done button click and invalidate timer
                 NSLog(@" invalidate timer");
                [mtimer invalidate];
            }
            //想干啥坏事写在这里面
  
        }];
        [[NSRunLoop currentRunLoop] addTimer:mtimer forMode:UITrackingRunLoopMode];

        [mtimer fire];
        //[mtimer fired];
 */
        _timer = [HWWeakTimer scheduledTimerWithTimeInterval:1.0f block:^(id userInfo) {
            NSLog(@"%@", userInfo);
            if (moviePlayer.player.rate == 0 &&
                (moviePlayer.isBeingDismissed || moviePlayer.nextResponder == nil)) {
                // Handle user Done button click and invalidate timer
                NSLog(@" invalidate timer");
                 [_timer invalidate];
                
                NSDictionary *dict =[[NSDictionary alloc]initWithObjectsAndKeys:@"Done",AVPlayerItemFailedToPlayToEndTimeErrorKey,nil];
                
                //创建通知
                
                NSNotification *notification =[NSNotification notificationWithName:AVPlayerItemFailedToPlayToEndTimeNotification object:[moviePlayer.player currentItem] userInfo:dict];
                
                //通过通知中心发送通知
                
                [[NSNotificationCenter defaultCenter] postNotification:notification];
                
            }
        } userInfo:@"Fire" repeats:YES];
        [_timer fire];


        
        NSURL *subtitleUrl      =   [self urlForPlaying:srt];
        
        if(subtitleUrl!=nil){
            // NSURL *subtitleURL   =  [NSURL fileURLWithPath:subtitleFile];
            //[moviePlayer addSubtitles];
            // [moviePlayer addSubtitles:self file:@"trailer_720p"];
            
            [moviePlayer addSubtitlessWithFile:subtitleUrl];
            //[moviePlayer addSubtitless:@"trailer_720p" ];
            
            //[moviePlayer open: subtitleURL];
            //[[moviePlayer addSubtitles].self open:subtitleURL];
        }
        
    }];
    
     


    //NSString *subtitleFile = [[NSBundle mainBundle] pathForResource:@"trailer_720p" ofType:@"srt"];
    

// [JHRotatoUtil forceOrientation: UIInterfaceOrientationLandscapeRight];
  //  [moviePlayer open];
    //moviePlayer.addSubtitles().open(file: subtitleURL)
/*
    self.orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (self.orientation == UIInterfaceOrientationPortrait || self.orientation == UIInterfaceOrientationPortraitUpsideDown) {
        //[JHRotatoUtil forceOrientation: UIInterfaceOrientationLandscapeRight];
    }else {
        
    }
    */
    
	// Listen for playback finishing
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(moviePlayBackDidFinish:)
												 name:AVPlayerItemDidPlayToEndTimeNotification
											   object:moviePlayer.player.currentItem];
    
    // Listen for errors
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayBackDidFinish:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:moviePlayer.player.currentItem];
    
	// Listen for click on the "Done" button
    
    // Deprecated.. AVPlayerController doesn't offer a "Done" listener... thanks apple. We'll listen for an error when playback finishes
       /* [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(doneButtonClick:)
                                                     name:MPMoviePlayerWillExitFullscreenNotification
                                                   object:nil];*/
    
	// Listen for orientation change
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(orientationChanged:)
												 name:UIDeviceOrientationDidChangeNotification
											   object:nil];
    
    // app进入前台
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterPlayground:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenDidChange:)
                                                 name:UIScreenDidConnectNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenDidChange:)
                                                 name:UIScreenDidDisconnectNotification
                                               object:nil];
    
}

- (void) moviePlayBackDidFinish:(NSNotification*)notification {
    NSLog(@"Playbacz zk did finish with auto close being %d, and error message being %@", shouldAutoClose, notification.userInfo);

    [_timer invalidate];
    
	NSDictionary *notificationUserInfo = [notification userInfo];
	NSNumber *errorValue = [notificationUserInfo objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
	NSString *errorMsg;
	if (errorValue) {
		NSError *mediaPlayerError = [notificationUserInfo objectForKey:@"error"];
		if (mediaPlayerError) {
			errorMsg = [mediaPlayerError localizedDescription];
		} else {
            errorMsg =  [NSString stringWithFormat:@"%@ Unknown error.", errorValue] ;
		}
		NSLog(@"Playback failed: %@", errorMsg);
	}

	//if (shouldAutoClose || [errorMsg length] != 0) {
		[self cleanup];
	//}
    CDVPluginResult* pluginResult;
    if ([errorMsg length] != 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMsg];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:true];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)cleanup {
	NSLog(@"Clean up");
	imageView = nil;
    initFullscreen = false;
	backgroundColor = nil;
    //[JHRotatoUtil forceOrientation: self.orientation];

	// Remove playback finished listener
	[[NSNotificationCenter defaultCenter]
							removeObserver:self
									  name:AVPlayerItemDidPlayToEndTimeNotification
									object:moviePlayer.player.currentItem];
	// Remove playback finished error listener
	[[NSNotificationCenter defaultCenter]
							removeObserver:self
									  name:AVPlayerItemFailedToPlayToEndTimeNotification
									object:moviePlayer.player.currentItem];
	// Remove orientation change listener
	[[NSNotificationCenter defaultCenter]
							removeObserver:self
									  name:UIDeviceOrientationDidChangeNotification
									object:nil];

    // remove app进入前台
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIScreenDidConnectNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIScreenDidDisconnectNotification
                                                  object:nil];
    
	if (moviePlayer) {
        [moviePlayer.player pause];
        [moviePlayer dismissViewControllerAnimated:YES completion:nil];
		moviePlayer = nil;
	}
}

- (void)screenDidChange:(NSNotification *)notification
{
    if(TRUE)return;
    NSArray            *screens;
    UIScreen        *aScreen;
    UIScreenMode    *mode;
    
    // 1.
    
    // Log the current screens and display modes
    screens = [UIScreen screens];

    
    uint32_t screenNum = 1;
    for (aScreen in screens) {
        NSArray *displayModes;
        displayModes = [aScreen availableModes];
        screenNum++;
    }
    
    NSUInteger screenCount = [screens count];
    
    if (screenCount > 1) {
        // 2.
        
        // Select first external screen
        self.extScreen = screens[1];
        
        self.availableModes = [self.extScreen availableModes];
        
        
        
        NSInteger selectedRow = 0;
        
        self.extScreen.currentMode = (self.availableModes)[selectedRow];
        
        if (self.extWindow == nil || !CGRectEqualToRect(self.extWindow.bounds, [self.extScreen bounds])) {
            // Size of window has actually changed
            
            // 4.
            self.extWindow = [[UIWindow alloc] initWithFrame:[self.extScreen bounds]];
            
            // 5.
            self.extWindow.screen = self.extScreen;
            
            UIView *view = [[UIView alloc] initWithFrame:[self.extWindow frame]];
            view.backgroundColor = [UIColor whiteColor];
            //[view addSubview:moviePlayer.view];
            superView = moviePlayer.view.superview;
            
           // [self.extWindow addSubview:view];
            [self.extWindow addSubview:moviePlayer.view];

            // 6.
            
            // 7.
            [self.extWindow makeKeyAndVisible];
            
            // Inform delegate that the external window has been created.
            //
            // NOTE: we ensure that the external window is sent to the delegate before
            // the preso mode is sent.
            
            
            // Enable preso mode option
            self.extWindow.hidden = NO;

        }
        
        

    }
    else {
        // Release external screen and window
        [superView addSubview:moviePlayer.view];
        self.extScreen = nil;
        
        self.extWindow = nil;
        self.availableModes = nil;


    }
}


@end
