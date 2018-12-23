//
//  MainViewController+RemoteControls.m
//
//  Created by Julio Cesar Sanchez Hernandez on 4/3/16.
//
//

#import "MainViewController+RemoteControls.h"

@implementation MainViewController (RemoteControls)

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"receivedEvent" object:receivedEvent];
}
- (void)viewDidAppear:(BOOL)animated {
    //    接受远程控制
    [self becomeFirstResponder];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

- (void)viewDidDisappear:(BOOL)animated {
    //    取消远程控制
    [self resignFirstResponder];
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
}

@end
