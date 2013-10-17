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
    MASShortcut *shortcutEscape;
    MASShortcut *shortcutEscape2;
    MASShortcut *shortcutMoveLeft;
    MASShortcut *shortcutMoveTop;
    MASShortcut *shortcutMoveBottom;
    MASShortcut *shortcutMoveRight;

    MASShortcut *shortcutResizeLeft;
    MASShortcut *shortcutResizeTop;
    MASShortcut *shortcutResizeBottom;
    MASShortcut *shortcutResizeRight;

    MASShortcut *shortcutResizeUpperLeft;
    MASShortcut *shortcutResizeUpperTop;
    MASShortcut *shortcutResizeUpperBottom;
    MASShortcut *shortcutResizeUpperRight;

    MASShortcut *shortcutQuickSwitch;
    MASShortcut *shortcutSwitchPrev;
    MASShortcut *shortcutSwitchPrev2;
    MASShortcut *shortcutSwitchNext;
    MASShortcut *shortcutSwitchNext2;

    MASShortcut *shortcutQuit;
    
    MASShortcut *shortcutSearchCommand;
    MASShortcut *shortcutSearchNext;
    MASShortcut *shortcutSearchPrev;

    MASShortcut *shortcutVolumeUp;
    MASShortcut *shortcutVolumeDown;

    NSMutableArray* quickGo;

    NSInteger repeatFactor;
    NSInteger quickSwitchOffset;
    
    BOOL commandMode;
    
}

@property (assign) IBOutlet NSWindow *window;
@property (unsafe_unretained) IBOutlet NSWindow *commandWindow;
@property (weak) IBOutlet NSTextField *commandText;
@property (nonatomic, retain) NSMutableArray *windows;

@end