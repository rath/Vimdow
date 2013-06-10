//
// Created by Jang Ho Hwang on 10/06/2013.
// Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//
// To change the template use AppCode | Preferences | File Templates.
//


#import "ScannedWindow.h"


@implementation ScannedWindow {

}
- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (!other || ![[other class] isEqual:[self class]])
        return NO;

    return [self isEqualToWindow:other];
}

- (BOOL)isEqualToWindow:(ScannedWindow *)window {
    if (self == window)
        return YES;
    if (window == nil)
        return NO;
    if (self.pid != window.pid && ![self.pid isEqualToNumber:window.pid])
        return NO;
    if (self.origin.x != window.origin.x)
        return NO;
    if (self.origin.y != window.origin.y)
        return NO;
    if (self.size.width != window.size.width)
        return NO;
    if (self.size.height != window.size.height)
        return NO;
    return YES;
}

- (NSUInteger)hash {
    NSUInteger hash = [self.pid hash];
    hash = hash * 31u + [[NSNumber numberWithDouble:self.origin.x] hash];
    hash = hash * 31u + [[NSNumber numberWithDouble:self.origin.y] hash];
    hash = hash * 31u + [[NSNumber numberWithDouble:self.size.width] hash];
    hash = hash * 31u + [[NSNumber numberWithDouble:self.size.height] hash];
    return hash;
}

@end