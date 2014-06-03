//
//  AppDelegate.m
//  switcher
//
//  Created by Jang Ho Hwang on 06/08/13.
//  Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AppDelegate.h"
#import "TargetWindow.h"
#import "ScannedWindow.h"
#import "AXUtil.h"

typedef struct {
    CGFloat x;
    CGFloat y;
    CGFloat w;
    CGFloat h;
} RectDelta;

@interface AppDelegate ()

{
    NSMutableArray *searchKeywords;
    TargetWindow *prevWindow;

}
- (IBAction)commandDidEnter:(id)sender;

@end

@implementation AppDelegate

void callbackWindowAttribute(const NSDictionary *inputDictionary, NSMutableSet *data) {
    NSDictionary *entry = (NSDictionary *) inputDictionary;

    int sharingState = [[entry objectForKey:(id)kCGWindowSharingState] intValue];
    int onScreen = [[entry objectForKey:(id)kCGWindowIsOnscreen] intValue];
    int windowLayer = [[entry objectForKey:(id)kCGWindowLayer] intValue];
    int windowAlpha = [[entry objectForKey:(id)kCGWindowAlpha] intValue];
    if(sharingState != kCGWindowSharingNone && onScreen==1 && windowLayer==0 && windowAlpha==1) {
//        NSLog(@"Dictionary: %@", entry);

        CGRect bounds;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[entry objectForKey:(id)kCGWindowBounds], &bounds);
        ScannedWindow *scan = [[ScannedWindow alloc] init];
        scan.pid = [entry objectForKey:(id)kCGWindowOwnerPID];
        scan.origin = bounds.origin;
        scan.size = bounds.size;
        scan.name = [entry objectForKey:(id)kCGWindowOwnerName];

        [data addObject:scan];

    }
}

static AXUIElementRef getFrontMostApp() {
    pid_t pid;
    ProcessSerialNumber psn;

    GetFrontProcess(&psn);
    GetProcessPID(&psn, &pid);

    return AXUIElementCreateApplication(pid);
}

- (NSWindow*)drawGuideWindow:(CGPoint)position guideNumber:(NSUInteger)number {
    int windowLevel = CGShieldingWindowLevel();
    NSScreen *screen = [NSScreen mainScreen];
    NSRect windowRect = NSRectFromCGRect(CGRectMake(position.x, screen.frame.size.height - position.y - 40.f, 40.0f, 40.0f));
    NSWindow *overlayWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                                          styleMask:NSBorderlessWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO
                                                             screen:[NSScreen mainScreen]];

    [overlayWindow setLevel:windowLevel];
    [overlayWindow setReleasedWhenClosed:YES];
    [overlayWindow setBackgroundColor:[NSColor colorWithCalibratedRed:0.0
                                                                green:0.0
                                                                 blue:0.0
                                                                alpha:0.5]];
    [overlayWindow setAlphaValue:1.0];
    [overlayWindow setOpaque:NO];
    [overlayWindow setIgnoresMouseEvents:YES];

    CATextLayer *l = [CATextLayer layer];
    l.string = [NSString stringWithFormat:@"%x", (unsigned int)number];
    l.fontSize = 32.0f;
    l.foregroundColor = [NSColor whiteColor].CGColor;
    l.alignmentMode = kCAAlignmentCenter;
    [l setPosition:CGPointMake(0, 0)];
    [l setBounds:CGRectMake(0, 0, 40, 40)];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)];
    view.wantsLayer = YES;
    view.layer = l;

    overlayWindow.contentView = view;
    [overlayWindow makeKeyAndOrderFront:nil];

    return overlayWindow;
}

- (void)clearGuideWindows {
     for(TargetWindow *window in self.windows) {
        CFRelease(window.app);
        CFRelease(window.window);
    }
    [self.windows removeAllObjects];
}

- (NSInteger)collectWindows {
    AXError error;

    NSMutableSet *data = [NSMutableSet set];
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), (CFArrayApplierFunction)&callbackWindowAttribute, (__bridge void*)data);
    CFRelease(windowList);

    NSMutableDictionary *pidDic = [NSMutableDictionary dictionary];
    for(ScannedWindow *window in data) {
        [pidDic setObject: [window name] forKey: [window pid]];
    }

    AXValueRef tmp;
    AXUIElementRef frontMostApp = getFrontMostApp();
    AXUIElementRef frontMostWindow = nil;
    error = AXUIElementCopyAttributeValue(frontMostApp, kAXFocusedWindowAttribute, (CFTypeRef*)&frontMostWindow);
    if (error==kAXErrorAPIDisabled) {
        showAXProblemAndTerminate(0);
    }
    
    CGPoint currentPosition;
    CGSize currentSize;
    if( error==kAXErrorSuccess ) {
        AXUIElementCopyAttributeValue(frontMostWindow, kAXPositionAttribute, (CFTypeRef *) &tmp);
        AXValueGetValue(tmp, kAXValueCGPointType, &currentPosition);
        CFRelease(tmp);
        AXUIElementCopyAttributeValue(frontMostWindow, kAXSizeAttribute, (CFTypeRef *) &tmp);
        AXValueGetValue(tmp, kAXValueCGSizeType, &currentSize);
        CFRelease(tmp);
    }

    [self clearGuideWindows];

    ScannedWindow *testScanWindow = [[ScannedWindow alloc] init];
    for (NSNumber *pid in pidDic) {
        NSString *name = pidDic[pid];
        
        AXUIElementRef app;
        CFArrayRef result = nil;
        app = AXUIElementCreateApplication([pid intValue]);
        AXError err = AXUIElementCopyAttributeValues(app, kAXWindowsAttribute, 0, 9999, &result);
        if( err!=kAXErrorSuccess || result==nil ) {
            CFRelease(app);
            continue;
        }

        for (CFIndex i = 0; i < CFArrayGetCount(result); i++) {
            CGPoint position;
            CGSize size;

            AXUIElementRef window = CFArrayGetValueAtIndex(result, i);

            AXUIElementCopyAttributeValue(window, kAXPositionAttribute, (CFTypeRef *) &tmp);
            AXValueGetValue(tmp, kAXValueCGPointType, &position);
            CFRelease(tmp);

            AXUIElementCopyAttributeValue(window, kAXSizeAttribute, (CFTypeRef *) &tmp);
            AXValueGetValue(tmp, kAXValueCGSizeType, &size);
            CFRelease(tmp);

            if( size.width < 50 || size.height < 50 )
                continue;

            testScanWindow.pid = pid;
            testScanWindow.origin = position;
            testScanWindow.size = size;

            if(![data containsObject:testScanWindow])
                continue;
            
            TargetWindow *value = [[TargetWindow alloc] init];
            value.app = CFRetain(app);
            value.window = CFRetain(window);
            value.x = position.x;
            value.y = position.y;
            value.width = size.width;
            value.height = size.height;
            value.isCurrent = NO;
            value.name = name;
            
            if (frontMostWindow != nil &&
                    CGPointEqualToPoint(currentPosition, position) &&
                    CGSizeEqualToSize(currentSize, size)) {
                value.isCurrent = YES;
            }

            [self.windows addObject:value];

        }

        CFRelease(result);
        CFRelease(app);
    }

    NSArray *sorted = [self.windows sortedArrayUsingComparator: ^(id a, id b) {
        TargetWindow *a0 = a;
        TargetWindow *a1 = b;
        if( a0.x < a1.x )
            return NSOrderedAscending;
        if( a0.x > a1.x )
            return NSOrderedDescending;
        return NSOrderedSame;
    }];
    [self.windows removeAllObjects];
    [self.windows addObjectsFromArray:sorted];

    if( frontMostWindow!=nil ) {
        CFRelease(frontMostWindow);
    }
    CFRelease(frontMostApp);

    NSInteger currentIndex = -1;
    for(NSUInteger i=0; i< [self.windows count]; i++) {
        TargetWindow *window = [self.windows objectAtIndex:i];
        if( window.isCurrent ) {
            currentIndex = i;
            break;
        }

    }
    return currentIndex;
}

- (void)switchWindow:(NSInteger)step withKeyword: (NSString*) keyword {
    NSInteger currentIndex = [self collectWindows];

    
    if(keyword == nil) {
        NSInteger newIndex = 0;

        if( repeatFactor > 0 ) {
            step = step * repeatFactor;
        }
        
        if( step < 0 && currentIndex+step < 0 ) { // No more previous
            newIndex = 0;
        } else
            if( step > 0 && currentIndex+step >= [self.windows count]-1 ) {  // No more next
                newIndex = [self.windows count] - 1;
            } else {
                newIndex = currentIndex + step;
            }
        TargetWindow *switchWindow = [self.windows objectAtIndex:newIndex];
        AXUIElementSetAttributeValue(switchWindow.window, kAXMainAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(switchWindow.app, kAXFrontmostAttribute, kCFBooleanTrue);
    }
    else if(self.windows.count > 0)  {
        
        NSInteger newIndex = -1;
        NSInteger nextIndex = currentIndex;
        NSInteger count = 1;
        NSInteger loopCount = 0;

        do {
            nextIndex += step;
            if(nextIndex < 0) {
                nextIndex = self.windows.count - 1;
            }
            else if(nextIndex >= self.windows.count) {
                nextIndex = 0;
            }

            TargetWindow *switchWindow = self.windows[nextIndex];
            if([switchWindow.name rangeOfString: keyword options: NSCaseInsensitiveSearch].location != NSNotFound) {
                if(count < repeatFactor) {
                    count ++;
                }
                else {
                    newIndex = nextIndex;
                    break;
                }
            }

            loopCount ++;
            if( loopCount > self.windows.count ) {
                break;
            }
        }
        while(nextIndex != currentIndex);

        if(newIndex >= 0 && newIndex < self.windows.count) {
            TargetWindow *switchWindow = [self.windows objectAtIndex:newIndex];
            AXUIElementSetAttributeValue(switchWindow.window, kAXMainAttribute, kCFBooleanTrue);
            AXUIElementSetAttributeValue(switchWindow.app, kAXFrontmostAttribute, kCFBooleanTrue);
        }
    }
    
    repeatFactor = -1;
}

- (void)prepareQuickSwitch {
    [self collectWindows];
    NSUInteger guideNumber = 1;
    NSUInteger index;
    for(index = quickSwitchOffset; index < self.windows.count && guideNumber < 10; index++) {
        TargetWindow *window = self.windows[index];
        NSWindow *guideWindow = [self drawGuideWindow:CGPointMake(window.x, window.y) guideNumber:guideNumber];
        window.guideWindow = guideWindow;
        guideNumber++;
    }

    if( index >= self.windows.count ) {
        quickSwitchOffset = -1;
    }
}

- (void)moveWithDelta:(RectDelta)delta  {
    AXError error;

    AXUIElementRef frontMostWindow;
    AXUIElementRef frontMost = getFrontMostApp();
    AXValueRef tmp;
    CGSize windowSize;
    CGPoint windowPosition;
    
    [self clearGuideWindows];
    if( repeatFactor > 0 ) {
        delta.x *= repeatFactor;
        delta.y *= repeatFactor;
        delta.w *= repeatFactor;
        delta.h *= repeatFactor;
    }

    error = AXUIElementCopyAttributeValue(frontMost, kAXFocusedWindowAttribute, (CFTypeRef*)&frontMostWindow);
    if (error==kAXErrorAPIDisabled)
        showAXProblemAndTerminate(0);
    
    if (error!=kAXErrorSuccess) {
        return;
    }
    AXUIElementCopyAttributeValue(frontMostWindow, kAXSizeAttribute, (CFTypeRef*)&tmp);
    AXValueGetValue(tmp, kAXValueCGSizeType, &windowSize);
    CFRelease(tmp);

    AXUIElementCopyAttributeValue(frontMostWindow, kAXPositionAttribute, (CFTypeRef*)&tmp);
    AXValueGetValue(tmp, kAXValueCGPointType, &windowPosition);
    CFRelease(tmp);

    if (delta.x != 0 || delta.y != 0) {
        windowPosition.x += delta.x;
        windowPosition.y += delta.y;

        tmp = AXValueCreate(kAXValueCGPointType, &windowPosition);
        error = AXUIElementSetAttributeValue(frontMostWindow, kAXPositionAttribute, tmp);
        CFRelease(tmp);
    }

    if (delta.w != 0 || delta.h != 0) {
        windowSize.width += delta.w;
        windowSize.height += delta.h;

        tmp = AXValueCreate(kAXValueCGSizeType, &windowSize);
        error = AXUIElementSetAttributeValue(frontMostWindow, kAXSizeAttribute, tmp);
        CFRelease(tmp);
    }

    CFRelease(frontMostWindow);
    CFRelease(frontMost);

    repeatFactor = -1;
}

- (void)exitNumbers {
    for (MASShortcut *s in quickGo) {
        [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", s.description]];
//        NSLog(@"Number description: %@", s.description);
    }
}
	
- (void)exitCommandMode {
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutEscape.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutEscape2.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutMoveLeft.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutMoveTop.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutMoveBottom.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutMoveRight.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeLeft.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeTop.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeBottom.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeRight.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeUpperLeft.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeUpperTop.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeUpperBottom.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutResizeUpperRight.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutQuickSwitch.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSwitchPrev.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSwitchPrev2.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSwitchNext.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSwitchNext2.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutQuit.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutVolumeDown.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutVolumeUp.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutPausePlayiTunes.description]];


    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSearchCommand.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSearchNext.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutSearchPrev.description]];

    [self exitNumbers];
    [self.windows removeAllObjects];
    repeatFactor = -1;
    quickSwitchOffset = -1;
    commandMode = NO;
}

- (void)increaseVolume:(Float32)amount {
    AudioDeviceID deviceId = 0;
    OSStatus result;
    AudioObjectPropertyAddress propertyAddress;

    // Get default output device
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    if (!AudioHardwareServiceHasProperty(kAudioObjectSystemObject, &propertyAddress)) {
        NSLog(@"Can't find default output device");
        return;
    }

    result = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, (UInt32[]) {sizeof(AudioDeviceID)}, &deviceId);
    if (kAudioHardwareNoError != result) {
        NSLog(@"Failed to get output device");
        return;
    }

    // Get the volume
    propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
    propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;

    if (!AudioHardwareServiceHasProperty(deviceId, &propertyAddress)) {
        NSLog(@"Failed to get virtual master volume properties for %0x", deviceId);
        return;
    }

    Float32 volume;
    UInt32 dataSize = sizeof(volume);
    result = AudioHardwareServiceGetPropertyData(deviceId, &propertyAddress, 0, NULL, &dataSize, &volume);
    if (kAudioHardwareNoError != result) {
        NSLog(@"Failed to get volume property");
        return;
    }

    volume += amount;
    if( volume < 0.0f ) {
        volume = 0.0f;
    }
    if( volume > 1.0f ) {
        volume = 1.0f;
    }

    result = AudioHardwareServiceSetPropertyData(deviceId, &propertyAddress, 0, NULL, dataSize, &volume);
    if (kAudioHardwareNoError != result) {
        NSLog(@"Failed to set volume property");
        return;
    }
    //NSLog(@"Volume reset: %4.2f", volume);
}

- (void)enterCommandMode {
    const double UNIT = 20;

    //        if( commandMode==YES ) {
    //            [self exitCommandMode];
    //            return;
    //        }
    quickSwitchOffset = -1;
    commandMode = YES;
    
    // Repeater
    for(NSUInteger index = 0; index<[quickGo count]; index++) {
        NSUInteger value = index==9 ? 0 : index+1;
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:[quickGo objectAtIndex:index] handler:^{
            if( repeatFactor !=-1 ) {
                repeatFactor *= 10;
            } else {
                repeatFactor = 0;
            }
            repeatFactor += value;
        }];
    }

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutEscape handler:^{
        [self exitCommandMode];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutEscape2 handler:^{
        [self exitCommandMode];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutQuickSwitch handler:^{
        if (quickSwitchOffset < 0) {
            quickSwitchOffset = 0;
        }
        else {
            quickSwitchOffset += 9;
        }
        [self exitNumbers];
        [self prepareQuickSwitch];

        int index = 1;
        for (MASShortcut *s in quickGo) {
            const NSUInteger i = index;
            [MASShortcut addGlobalHotkeyMonitorWithShortcut:s handler:^{
                if (quickSwitchOffset == -1) {
                    quickSwitchOffset = 0;
                }
                NSUInteger windowIndex = i - 1 + quickSwitchOffset;
                if ([self.windows count] >= windowIndex + 1) {
                    TargetWindow *targetWindow = [self.windows objectAtIndex:windowIndex];
                    AXUIElementSetAttributeValue(targetWindow.window, kAXMainAttribute, kCFBooleanTrue);
                    AXUIElementSetAttributeValue(targetWindow.app, kAXFrontmostAttribute, kCFBooleanTrue);
                }
                [self exitCommandMode];
            }];
            index++;
        }
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutMoveLeft handler:^{
        RectDelta delta = {-UNIT, 0, 0, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutMoveRight handler:^{
        RectDelta delta = {UNIT, 0, 0, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutMoveTop handler:^{
        RectDelta delta = {0, -UNIT, 0, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutMoveBottom handler:^{
        RectDelta delta = {0, UNIT, 0, 0};
        [self moveWithDelta:delta];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeLeft handler:^{
        RectDelta delta = {0, 0, -UNIT, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeRight handler:^{
        RectDelta delta = {0, 0, UNIT, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeTop handler:^{
        RectDelta delta = {0, 0, 0, -UNIT};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeBottom handler:^{
        RectDelta delta = {0, 0, 0, UNIT};
        [self moveWithDelta:delta];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeUpperLeft handler:^{
        RectDelta delta = {-UNIT, 0, UNIT, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeUpperRight handler:^{
        RectDelta delta = {UNIT, 0, -UNIT, 0};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeUpperTop handler:^{
        RectDelta delta = {0, -UNIT, 0, UNIT};
        [self moveWithDelta:delta];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutResizeUpperBottom handler:^{
        RectDelta delta = {0, UNIT, 0, -UNIT};
        [self moveWithDelta:delta];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutQuit handler:^{
        [NSApp terminate:self];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutVolumeDown handler:^{
        [self increaseVolume:-0.05f];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutVolumeUp handler:^{
        [self increaseVolume:0.05f];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutPausePlayiTunes handler:^{
        NSString *toggleScript = [NSString stringWithFormat:
@"tell application \"iTunes\"\n\
  if player state is playing then\n\
    pause\n\
  else if player state is paused then\n\
    play\n\
  end if\n\
end tell"];
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:toggleScript];
        NSDictionary *errorInfo;
        [script executeAndReturnError:&errorInfo];
        if (errorInfo!=nil ) {
            NSLog(@"iTunes AppleScript error: %@", [errorInfo description]);
        }
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSearchCommand handler:^{
        NSInteger index = [self collectWindows];
        if (index >= 0 && index < self.windows.count) {
            prevWindow = self.windows[index];
        }

        [self exitCommandMode];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutEscape handler:^{
            dispatch_async(dispatch_get_main_queue(), ^{ /* because esc hot key monitor cannot be removed in this block */
                [self.commandWindow resignKeyWindow];
            });
        }];
        [self.commandText setStringValue:@""];
        [self.commandWindow makeKeyAndOrderFront:self];
        [NSApp activateIgnoringOtherApps:YES];
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSearchNext handler:^{
        if (searchKeywords.count > 0) {
            [self switchWindow:1 withKeyword:searchKeywords[searchKeywords.count - 1]];
        }
    }];

    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSearchPrev handler:^{
        if (searchKeywords.count > 0) {
            [self switchWindow:-1 withKeyword:searchKeywords[searchKeywords.count - 1]];
        }
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self.window setIsVisible:FALSE];
    
    SInt32 osxVersion = 0;
    Gestalt(gestaltSystemVersion, &osxVersion);
    
    if (osxVersion < 0x1010) {
        Boolean axEnabled = AXAPIEnabled();
        if( !axEnabled ) {
            showAXProblemAndTerminate(osxVersion);
            return;
        }
    }
    
    self.windows = [[NSMutableArray alloc] initWithCapacity:20];
    repeatFactor = -1;
    commandMode = NO;

    shortcutEscape = [MASShortcut shortcutWithKeyCode:kVK_Escape modifierFlags:0];
    shortcutEscape2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Period modifierFlags:0];
    shortcutMoveLeft = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:0];
    shortcutMoveTop = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:0];
    shortcutMoveBottom = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:0];
    shortcutMoveRight = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:0];

    shortcutResizeLeft = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSAlternateKeyMask];
    shortcutResizeTop = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSAlternateKeyMask];
    shortcutResizeBottom = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSAlternateKeyMask];
    shortcutResizeRight = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSAlternateKeyMask];

    shortcutResizeUpperLeft = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSShiftKeyMask];
    shortcutResizeUpperTop = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSShiftKeyMask];
    shortcutResizeUpperBottom = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSShiftKeyMask];
    shortcutResizeUpperRight = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSShiftKeyMask];

    shortcutSwitchPrev = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    shortcutSwitchPrev2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    shortcutSwitchNext = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    shortcutSwitchNext2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSControlKeyMask|NSShiftKeyMask];

    shortcutQuit = [MASShortcut shortcutWithKeyCode:kVK_ANSI_X modifierFlags:0];

    shortcutVolumeDown = [MASShortcut shortcutWithKeyCode:kVK_F9 modifierFlags:0];
    shortcutVolumeUp = [MASShortcut shortcutWithKeyCode:kVK_F10 modifierFlags:0];
    shortcutPausePlayiTunes = [MASShortcut shortcutWithKeyCode:kVK_F13 modifierFlags:0];

    shortcutSearchCommand = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Slash modifierFlags:0];
    shortcutSearchNext = [MASShortcut shortcutWithKeyCode:kVK_ANSI_N modifierFlags:0];
    shortcutSearchPrev = [MASShortcut shortcutWithKeyCode:kVK_ANSI_N modifierFlags:NSShiftKeyMask];
    
    quickGo = [NSMutableArray arrayWithCapacity:10];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_1 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_2 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_3 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_4 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_5 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_6 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_7 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_8 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_9 modifierFlags:0]];
    [quickGo addObject:[MASShortcut shortcutWithKeyCode:kVK_ANSI_0 modifierFlags:0]];

    shortcutQuickSwitch = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Q modifierFlags:0];
    
    MASShortcut *shortcut = [MASShortcut shortcutWithKeyCode:kVK_ANSI_A modifierFlags:NSAlternateKeyMask];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcut handler:^{
        [self enterCommandMode];
    }];


    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSwitchPrev handler:^{
        [self switchWindow:-1 withKeyword:nil];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSwitchPrev2 handler:^{
        [self switchWindow:-1 withKeyword:nil];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSwitchNext handler:^{
        [self switchWindow:1 withKeyword:nil];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcutSwitchNext2 handler:^{
        [self switchWindow:1 withKeyword:nil];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commandWindowDidOpen) name:NSWindowDidBecomeKeyNotification object:self.commandWindow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(commandWindowDidOpen) name:NSWindowDidBecomeMainNotification object:self.commandWindow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(closeCommandWindow) name:NSWindowDidResignKeyNotification object:self.commandWindow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(closeCommandWindow) name:NSWindowDidResignMainNotification object:self.commandWindow];

    searchKeywords = [NSMutableArray array];
}

- (void)commandWindowDidOpen {
    [self.commandText becomeFirstResponder];
}

- (void)closeCommandWindow {
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", shortcutEscape.description]];
    [self.commandWindow orderOut: self];
    [self enterCommandMode];
    if(prevWindow != nil) {
        AXUIElementSetAttributeValue(prevWindow.window, kAXMainAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(prevWindow.app, kAXFrontmostAttribute, kCFBooleanTrue);
        prevWindow = nil;
    }
}

- (IBAction)commandDidEnter:(id)sender {
    prevWindow = nil;
    [self.commandWindow resignKeyWindow];

    NSString *keyword = self.commandText.stringValue;

    if(keyword.length > 0 &&
       (searchKeywords.count == 0 || ![keyword isEqualToString: searchKeywords[searchKeywords.count - 1]])) {
        [searchKeywords addObject: keyword];
        [self switchWindow:1 withKeyword: keyword];
    }
}


@end
