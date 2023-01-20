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

    int onScreen = [[entry objectForKey:(id)kCGWindowIsOnscreen] intValue];
    int windowLayer = [[entry objectForKey:(id)kCGWindowLayer] intValue];
    int windowAlpha = [[entry objectForKey:(id)kCGWindowAlpha] intValue];
    if(onScreen==1 && windowLayer==0 && windowAlpha==1) {
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
    NSScreen *screen = [NSScreen screens].firstObject;
    NSRect windowRect = NSRectFromCGRect(CGRectMake(position.x + 4, screen.frame.size.height - position.y - 36.f - 4, 36.0f, 36.0f));
    NSWindow *overlayWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                                          styleMask:NSWindowStyleMaskBorderless
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO
                                                             screen:nil];
    [overlayWindow setBackgroundColor:[NSColor colorWithCalibratedRed:0.0
                                                                green:0.0
                                                                 blue:0.0
                                                                alpha:0.40]];
    [overlayWindow setOpaque:NO];
    [overlayWindow setIgnoresMouseEvents:YES];
    [overlayWindow setReleasedWhenClosed:YES];
    [overlayWindow setLevel:CGShieldingWindowLevel()];

    CATextLayer *l = [CATextLayer layer];
    l.string = [NSString stringWithFormat:@"%x", (unsigned int)number];
    l.fontSize = 28.0f;
    l.foregroundColor = [NSColor whiteColor].CGColor;
    l.alignmentMode = kCAAlignmentCenter;
    l.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    [l setPosition:CGPointMake(0, 0)];
    [l setBounds:CGRectMake(0, 0, 36, 36)];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 36, 36)];
    view.wantsLayer = YES;
    view.layer = l;

    overlayWindow.contentView = view;
    [overlayWindow makeKeyAndOrderFront:nil];

    return overlayWindow;
}

- (void)clearWindows {
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

    [self clearWindows];

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
            value.guideWindow = nil;
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
    
    [self clearWindows];
    if( repeatFactor > 0 ) {
        delta.x *= repeatFactor;
        delta.y *= repeatFactor;
        delta.w *= repeatFactor;
        delta.h *= repeatFactor;
    }

    error = AXUIElementCopyAttributeValue(frontMost, kAXFocusedWindowAttribute, (CFTypeRef*)&frontMostWindow);
    if (error==kAXErrorAPIDisabled) {
        showAXProblemAndTerminate(0);
    }

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

- (NSArray*)screenRects {
    NSMutableArray *screenRects = [[NSMutableArray alloc] init];
    for (NSScreen *screen in [NSScreen screens]) {
        CGDirectDisplayID displayID = [[screen deviceDescription][@"NSScreenNumber"] unsignedIntValue];
        CGRect rect = CGDisplayBounds(displayID);
        [screenRects addObject:[NSValue valueWithRect:rect]];
    }
    return screenRects;
}

- (void)moveToNextScreen {
    AXError error;

    AXUIElementRef frontMostWindow;
    AXUIElementRef frontMost = getFrontMostApp();
    AXValueRef tmp;

    CGSize windowSize;
    CGPoint windowPosition;

    error = AXUIElementCopyAttributeValue(frontMost, kAXFocusedWindowAttribute, (CFTypeRef*)&frontMostWindow);
    if (error==kAXErrorAPIDisabled) {
        showAXProblemAndTerminate(0);
    }
    if (error!=kAXErrorSuccess) {
        return;
    }
    AXUIElementCopyAttributeValue(frontMostWindow, kAXPositionAttribute, (CFTypeRef*)&tmp);
    AXValueGetValue(tmp, kAXValueCGPointType, &windowPosition);
    CFRelease(tmp);

    NSArray *screenRects = [self screenRects];
    int currentScreen = 0;
    for (int i=0; i<screenRects.count; i++) {
        CGRect rect = [[screenRects objectAtIndex:i] rectValue];
        bool contain = CGRectContainsPoint(rect, windowPosition);
        if (contain == YES) {
            currentScreen = i;
        }
    }

    int nextScreen = currentScreen + 1;
    if (nextScreen >= screenRects.count) {
        nextScreen = 0;
    }

    CGRect nextRect = [[screenRects objectAtIndex:nextScreen] rectValue];
    windowPosition.x = nextRect.origin.x + 0;
    windowPosition.y = nextRect.origin.y + 0;
    windowSize.width = nextRect.size.width - 0;
    windowSize.height = nextRect.size.height - 0;

    tmp = AXValueCreate(kAXValueCGPointType, &windowPosition);
    error = AXUIElementSetAttributeValue(frontMostWindow, kAXPositionAttribute, tmp);
    CFRelease(tmp);
    tmp = AXValueCreate(kAXValueCGSizeType, &windowSize);
    error = AXUIElementSetAttributeValue(frontMostWindow, kAXSizeAttribute, tmp);
    CFRelease(tmp);
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
    propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume;
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
}

- (void)addHotKey: (MASShortcut*)shortcut handler: (dispatch_block_t)action {
    [[MASShortcutMonitor sharedMonitor] registerShortcut:shortcut withAction:action];
}

- (void)removeHotKey: (MASShortcut*)shortcut {
    [[MASShortcutMonitor sharedMonitor] unregisterShortcut:shortcut];
}

- (void)enterCommandMode {
    const double UNIT = 20;

    quickSwitchOffset = -1;
    commandMode = YES;
    
    // Repeater

    for(NSUInteger index = 0; index<[quickGo count]; index++) {
        NSUInteger value = index==9 ? 0 : index+1;
        [self addHotKey:[quickGo objectAtIndex: index] handler:^{
            if( repeatFactor !=-1 ) {
                repeatFactor *= 10;
            } else {
                repeatFactor = 0;
            }
            repeatFactor += value;
        }];
    }

    __unsafe_unretained typeof(self) self_ = self;
    [self addHotKey:shortcutEscape handler:^{
        [self_ exitCommandMode];
    }];
    [self addHotKey:shortcutEscape2 handler:^{
        [self_ exitCommandMode];
    }];
    [self addHotKey:shortcutQuickSwitch handler:^{
        if (quickSwitchOffset < 0) {
            quickSwitchOffset = 0;
        }
        else {
            quickSwitchOffset += 9;
        }
        [self_ exitNumbers];
        [self_ prepareQuickSwitch];

        int index = 1;
        for (MASShortcut *s in self_->quickGo) {
            const NSUInteger i = index;
            [self_ addHotKey:s handler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (quickSwitchOffset == -1) {
                        quickSwitchOffset = 0;
                    }
                    NSUInteger windowIndex = i - 1 + quickSwitchOffset;
                    if ([self_.windows count] >= windowIndex + 1) {
                        TargetWindow *targetWindow = [self_.windows objectAtIndex:windowIndex];
                        AXUIElementSetAttributeValue(targetWindow.window, kAXMainAttribute, kCFBooleanTrue);
                        AXUIElementSetAttributeValue(targetWindow.app, kAXFrontmostAttribute, kCFBooleanTrue);
                        CGDisplayMoveCursorToPoint(0, CGPointMake(targetWindow.x + targetWindow.width / 2, targetWindow.y + targetWindow.height / 2));
                    }
                    [self_ exitCommandMode];
                });
            }];
            index++;
        }
    }];

    [self addHotKey:shortcutMoveLeft handler:^{
        RectDelta delta = {-UNIT, 0, 0, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutMoveRight handler:^{
        RectDelta delta = {UNIT, 0, 0, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutMoveTop handler:^{
        RectDelta delta = {0, -UNIT, 0, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutMoveBottom handler:^{
        RectDelta delta = {0, UNIT, 0, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeLeft handler:^{
        RectDelta delta = {0, 0, -UNIT, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeRight handler:^{
        RectDelta delta = {0, 0, UNIT, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeTop handler:^{
        RectDelta delta = {0, 0, 0, -UNIT};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeBottom handler:^{
        RectDelta delta = {0, 0, 0, UNIT};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeUpperLeft handler:^{
        RectDelta delta = {-UNIT, 0, UNIT, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeUpperRight handler:^{
        RectDelta delta = {UNIT, 0, -UNIT, 0};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeUpperTop handler:^{
        RectDelta delta = {0, -UNIT, 0, UNIT};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutResizeUpperBottom handler:^{
        RectDelta delta = {0, UNIT, 0, -UNIT};
        [self_ moveWithDelta:delta];
    }];
    [self addHotKey:shortcutQuit handler:^{
        [NSApp terminate:self_];
    }];

    [self addHotKey:shortcutVolumeDown handler:^{
        [self_ increaseVolume:-0.05f];
    }];
    [self addHotKey:shortcutVolumeUp handler:^{
        [self_ increaseVolume:0.05f];
    }];

    [self addHotKey:shortcutPausePlayiTunes handler:^{
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

    [self addHotKey:shortcutSearchCommand handler:^{
        NSInteger index = [self_ collectWindows];
        if (index >= 0 && index < self_.windows.count) {
            prevWindow = self_.windows[index];
        }

        [self_ exitCommandMode];
        [self_ addHotKey:self_->shortcutEscape handler:^{
            dispatch_async(dispatch_get_main_queue(), ^{ // because esc hot key monitor cannot be removed in this block
                [self_.commandWindow resignKeyWindow];
            });
        }];
        [self_.commandText setStringValue:@""];
        [self_.commandWindow makeKeyAndOrderFront:self_];
        [NSApp activateIgnoringOtherApps:YES];
    }];

    [self addHotKey:shortcutSearchNext handler:^{
        if (searchKeywords.count > 0) {
            [self_ switchWindow:1 withKeyword:self_->searchKeywords[searchKeywords.count - 1]];
        }
    }];

    [self addHotKey:shortcutSearchPrev handler:^{
        if (searchKeywords.count > 0) {
            [self_ switchWindow:-1 withKeyword:self_->searchKeywords[searchKeywords.count - 1]];
        }
    }];

    [self addHotKey:shortcutMoveToNextScreen handler:^{
        [self_ moveToNextScreen];
    }];
    [self addHotKey:shortcutMoveToNextScreen2 handler:^{
        [self_ moveToNextScreen];
    }];
}

- (void)exitNumbers {
    for (MASShortcut *s in quickGo) {
        [self removeHotKey:s];
//        NSLog(@"Number description: %@", s.description);
    }
}

- (void)exitCommandMode {
    
    NSArray *shortcuts = @[
        shortcutEscape,
        shortcutEscape2,
        shortcutMoveLeft,
        shortcutMoveTop,
        shortcutMoveBottom,
        shortcutMoveRight,
        shortcutResizeLeft,
        shortcutResizeTop,
        shortcutResizeBottom,
        shortcutResizeRight,
        shortcutResizeUpperLeft,
        shortcutResizeUpperTop,
        shortcutResizeUpperBottom,
        shortcutResizeUpperRight,
        shortcutQuickSwitch,
        shortcutQuit,
        shortcutVolumeUp,
        shortcutVolumeDown,
        shortcutPausePlayiTunes,
        shortcutSearchCommand,
        shortcutSearchNext,
        shortcutSearchPrev,
        shortcutMoveToNextScreen,
        shortcutMoveToNextScreen2,
    ];
    
    for (MASShortcut *s in shortcuts) {
        [self removeHotKey:s];
    }

    [self exitNumbers];
    [self clearWindows];
    repeatFactor = -1;
    quickSwitchOffset = -1;
    commandMode = NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self.window setIsVisible:FALSE];
    
    self.windows = [[NSMutableArray alloc] initWithCapacity:20];
    repeatFactor = -1;
    commandMode = NO;

    shortcutEscape = [MASShortcut shortcutWithKeyCode:kVK_Escape modifierFlags:0];
    shortcutEscape2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Period modifierFlags:0];
    shortcutMoveLeft = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:0];
    shortcutMoveTop = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:0];
    shortcutMoveBottom = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:0];
    shortcutMoveRight = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:0];
    shortcutMoveToNextScreen = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSControlKeyMask|NSAlternateKeyMask];
    shortcutMoveToNextScreen2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSControlKeyMask|NSAlternateKeyMask];

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
    
    __weak AppDelegate *self_ = self;
    MASShortcut *shortcut = [MASShortcut shortcutWithKeyCode:kVK_ANSI_A modifierFlags:NSControlKeyMask|NSShiftKeyMask];

    [self addHotKey:shortcut handler:^{
//        if (commandMode) {
//            [self_ exitCommandMode];
//        } else {
            [self_ enterCommandMode];
//        }
    }];

    [self addHotKey:shortcutSwitchPrev handler:^{
        [self_ switchWindow:-1 withKeyword:nil];
    }];
    [self addHotKey:shortcutSwitchPrev2 handler:^{
        [self_ switchWindow:-1 withKeyword:nil];
    }];
    [self addHotKey:shortcutSwitchNext handler:^{
        [self_ switchWindow:1 withKeyword:nil];
    }];
    [self addHotKey:shortcutSwitchNext2 handler:^{
        [self_ switchWindow:1 withKeyword:nil];
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
    [self removeHotKey:shortcutEscape];
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
