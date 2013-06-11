//
//  AppDelegate.m
//  switcher
//
//  Created by Jang Ho Hwang on 06/08/13.
//  Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "AppDelegate.h"
#import "TargetWindow.h"
#import "ScannedWindow.h"

typedef struct {
    CGFloat x;
    CGFloat y;
    CGFloat w;
    CGFloat h;
} RectDelta;

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
        CFRetain(window.app);
        CFRetain(window.window);
    }
    [self.windows removeAllObjects];
}

- (NSInteger)collectWindows {
    AXError error;

    NSMutableSet *data = [NSMutableSet set];
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), &callbackWindowAttribute, (__bridge void*)data);
    CFRelease(windowList);

    NSMutableSet *pidSet = [NSMutableSet set];
    for(ScannedWindow *window in data) {
        [pidSet addObject:[window pid]];
    }

    AXValueRef tmp;
    AXUIElementRef frontMostApp = getFrontMostApp();
    AXUIElementRef frontMostWindow = nil;
    error = AXUIElementCopyAttributeValue(frontMostApp, kAXFocusedWindowAttribute, (CFTypeRef*)&frontMostWindow);

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
    for (NSNumber *pid in pidSet) {
        AXUIElementRef app;
        CFArrayRef result;
        app = AXUIElementCreateApplication([pid intValue]);
        AXUIElementCopyAttributeValues(app, kAXWindowsAttribute, 0, 9999, &result);

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

- (void)switchWindow:(NSInteger)step {
    NSInteger currentIndex = [self collectWindows];
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

- (void)quickSwitch {
    [self collectWindows];
    NSUInteger guideNumber = 1;
    for(TargetWindow *window in self.windows) {
        NSWindow *guideWindow = [self drawGuideWindow:CGPointMake(window.x, window.y) guideNumber:guideNumber];
        window.guideWindow = guideWindow;
        guideNumber++;
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
    if( error!=kAXErrorSuccess )
        return;
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
        AXUIElementSetAttributeValue(frontMostWindow, kAXPositionAttribute, tmp);
        CFRelease(tmp);
    }

    if (delta.w != 0 || delta.h != 0) {
        windowSize.width += delta.w;
        windowSize.height += delta.h;

        tmp = AXValueCreate(kAXValueCGSizeType, &windowSize);
        AXUIElementSetAttributeValue(frontMostWindow, kAXSizeAttribute, tmp);
        CFRelease(tmp);
    }

    CFRelease(frontMostWindow);
    CFRelease(frontMost);

    repeatFactor = -1;
}

- (void)exitNumbers {
    for (MASShortcut *s in quickGo) {
        [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", s.description]];
        NSLog(@"Number description: %@", s.description);
    }
}

- (void)exitCommandMode {
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", escape.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", escape2.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", leftMove.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", topMove.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", bottomMove.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", rightMove.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", leftSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", topSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", bottomSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", rightSize.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", upperLeftSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", upperTopSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", upperBottomSize.description]];
    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", upperRightSize.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", quickSwitch.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", switchPrev.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", switchPrev2.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", switchNext.description]];
//    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", switchNext2.description]];

    [MASShortcut removeGlobalHotkeyMonitor:[NSString stringWithFormat:@"%@", quit.description]];

    [self exitNumbers];
    [self.windows removeAllObjects];
    repeatFactor = -1;
    commandMode = NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self.window setIsVisible:FALSE];

    Boolean axEnabled = AXAPIEnabled();
    if( !axEnabled ) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSCriticalAlertStyle;
        alert.messageText = @"Unabled to launch";
        alert.informativeText = @"This program use accessibility API.\n"
                "You can turn it on in\n"
                "System Preferences > Accessibility > \n"
                "[X] Enabled access for assistive devices.";
        [alert runModal];
        [NSApp terminate:self];
        return;
    }

    self.windows = [[NSMutableArray alloc] initWithCapacity:20];
    repeatFactor = -1;
    commandMode = NO;

    const double UNIT = 20;

    escape = [MASShortcut shortcutWithKeyCode:kVK_Escape modifierFlags:0];
    escape2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Period modifierFlags:0];
    leftMove = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:0];
    topMove = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:0];
    bottomMove = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:0];
    rightMove = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:0];

    leftSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSAlternateKeyMask];
    topSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSAlternateKeyMask];
    bottomSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSAlternateKeyMask];
    rightSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSAlternateKeyMask];

    upperLeftSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSShiftKeyMask];
    upperTopSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSShiftKeyMask];
    upperBottomSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSShiftKeyMask];
    upperRightSize = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSShiftKeyMask];

    switchPrev = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    switchPrev2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_J modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    switchNext = [MASShortcut shortcutWithKeyCode:kVK_ANSI_L modifierFlags:NSControlKeyMask|NSShiftKeyMask];
    switchNext2 = [MASShortcut shortcutWithKeyCode:kVK_ANSI_K modifierFlags:NSControlKeyMask|NSShiftKeyMask];

    quit = [MASShortcut shortcutWithKeyCode:kVK_ANSI_X modifierFlags:0];

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

    quickSwitch = [MASShortcut shortcutWithKeyCode:kVK_ANSI_Q modifierFlags:0];

    MASShortcut *shortcut = [MASShortcut shortcutWithKeyCode:kVK_ANSI_A modifierFlags:NSAlternateKeyMask];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:shortcut handler:^{
//        if( commandMode==YES ) {
//            [self exitCommandMode];
//            return;
//        }
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

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:escape handler:^{
            [self exitCommandMode];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:escape2 handler:^{
            [self exitCommandMode];
        }];

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:quickSwitch handler:^{
            [self exitNumbers];
            [self quickSwitch];

            int index = 1;
            for (MASShortcut *s in quickGo) {
                const NSUInteger i = index;
                [MASShortcut addGlobalHotkeyMonitorWithShortcut:s handler:^{
                    NSUInteger windowIndex = i - 1;
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

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:leftMove handler:^{
            RectDelta delta = {-UNIT, 0, 0, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:rightMove handler:^{
            RectDelta delta = {UNIT, 0, 0, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:topMove handler:^{
            RectDelta delta = {0, -UNIT, 0, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:bottomMove handler:^{
            RectDelta delta = {0, UNIT, 0, 0};
            [self moveWithDelta:delta];
        }];

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:leftSize handler:^{
            RectDelta delta = {0, 0, -UNIT, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:rightSize handler:^{
            RectDelta delta = {0, 0, UNIT, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:topSize handler:^{
            RectDelta delta = {0, 0, 0, -UNIT};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:bottomSize handler:^{
            RectDelta delta = {0, 0, 0, UNIT};
            [self moveWithDelta:delta];
        }];

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:upperLeftSize handler:^{
            RectDelta delta = {-UNIT, 0, UNIT, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:upperRightSize handler:^{
            RectDelta delta = {UNIT, 0, -UNIT, 0};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:upperTopSize handler:^{
            RectDelta delta = {0, -UNIT, 0, UNIT};
            [self moveWithDelta:delta];
        }];
        [MASShortcut addGlobalHotkeyMonitorWithShortcut:upperBottomSize handler:^{
            RectDelta delta = {0, UNIT, 0, -UNIT};
            [self moveWithDelta:delta];
        }];

        [MASShortcut addGlobalHotkeyMonitorWithShortcut:quit handler:^{
            [NSApp terminate:self];
        }];
    }];


    [MASShortcut addGlobalHotkeyMonitorWithShortcut:switchPrev handler:^{
        [self switchWindow:-1];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:switchPrev2 handler:^{
        [self switchWindow:-1];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:switchNext handler:^{
        [self switchWindow:1];
    }];
    [MASShortcut addGlobalHotkeyMonitorWithShortcut:switchNext2 handler:^{
        [self switchWindow:1];
    }];
}

@end