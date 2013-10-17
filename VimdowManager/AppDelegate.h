//
//  AppDelegate.h
//  switcher
//
//  Created by Jang Ho Hwang on 06/08/13.
//  Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASShortcut.h"
#import "MASShortcut+Monitoring.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    MASShortcut *escape;
    MASShortcut *escape2;
    MASShortcut *leftMove;
    MASShortcut *topMove;
    MASShortcut *bottomMove;
    MASShortcut *rightMove;

    MASShortcut *leftSize;
    MASShortcut *topSize;
    MASShortcut *bottomSize;
    MASShortcut *rightSize;

    MASShortcut *upperLeftSize;
    MASShortcut *upperTopSize;
    MASShortcut *upperBottomSize;
    MASShortcut *upperRightSize;

    MASShortcut *quickSwitch;
    MASShortcut *switchPrev;
    MASShortcut *switchPrev2;
    MASShortcut *switchNext;
    MASShortcut *switchNext2;

    MASShortcut *quit;
    
    MASShortcut *searchCommand;
    MASShortcut *searchNext;
    MASShortcut *searchPrev;

    MASShortcut *volumeUp;
    MASShortcut *volumeDown;

    NSMutableArray* quickGo;

    MASShortcut *shortcutTest;

    NSInteger repeatFactor;
    NSInteger quickSwitchOffset;
    
    BOOL commandMode;
    
}

@property (assign) IBOutlet NSWindow *window;
@property (unsafe_unretained) IBOutlet NSWindow *commandWindow;
@property (weak) IBOutlet NSTextField *commandText;
@property (nonatomic, retain) NSMutableArray *windows;

@end