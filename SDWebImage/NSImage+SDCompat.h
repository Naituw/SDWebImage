//
//  NSImage+SDCompat.h
//  SDWebImage
//
//  Created by Wutian on 13-9-22.
//  Copyright (c) 2013年 Dailymotion. All rights reserved.
//

#if !TARGET_IPHONE_OS
#import <Cocoa/Cocoa.h>

@interface NSImage (SDCompat)

+ (instancetype)imageWithCGImage:(CGImageRef)imageRef;

- (CGFloat)scale;

- (NSArray *)images;

@end
#endif
