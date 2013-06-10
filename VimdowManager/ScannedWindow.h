//
// Created by Jang Ho Hwang on 10/06/2013.
// Copyright (c) 2013 Jang Ho Hwang. All rights reserved.
//
// To change the template use AppCode | Preferences | File Templates.
//


#import <Foundation/Foundation.h>


@interface ScannedWindow : NSValue
@property (nonatomic, retain) NSNumber *pid;
@property CGPoint origin;
@property CGSize size;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToWindow:(ScannedWindow *)window;
- (NSUInteger)hash;
@end