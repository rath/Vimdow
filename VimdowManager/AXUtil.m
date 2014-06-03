//
//  AXUtil.c
//  VimdowManager
//
//  Created by Jang Ho Hwang on 03/06/2014.
//  Copyright (c) 2014 Jang Ho Hwang. All rights reserved.
//
#import "AXUtil.h"

void showAXProblemAndTerminate(SInt32 osxVersion) {
    if (osxVersion==0) {
        Gestalt(gestaltSystemVersion, &osxVersion);
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSCriticalAlertStyle;
    alert.messageText = @"Problem with Accessibility API";
    if (osxVersion >= 0x1009) {
        alert.informativeText = @"This program uses accessibility API.\n" 
        "You can turn it on in\n" 
        "System Preferences > Security & Privacy\n"
        "> Accessibility";
    } else {
        alert.informativeText = @"This program uses accessibility API.\n" 
        "You can turn it on in\n"
        "System Preferences > Accessibility > \n"
        "[x] Enabled access for assistive devices.";
    }
    [alert runModal];
    [NSApp terminate:nil];
}
