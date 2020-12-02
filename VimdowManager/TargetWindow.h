//
// Created by Jang Ho Hwang on 10/06/2013.
// Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//
// To change the template use AppCode | Preferences | File Templates.
//


#import <Foundation/Foundation.h>


@interface TargetWindow : NSObject
@property CGFloat x;
@property CGFloat y;
@property CGFloat width;
@property CGFloat height;
@property BOOL isCurrent;
@property (nonatomic, retain) NSWindow *guideWindow;
@property (nonatomic) AXUIElementRef window;
@property (nonatomic) AXUIElementRef app;
@property (nonatomic, strong) NSString *name;

@end
