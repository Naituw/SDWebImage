//
//  NSImage+SDCompat.m
//  SDWebImage
//
//  Created by Wutian on 13-9-22.
//  Copyright (c) 2013年 Dailymotion. All rights reserved.
//

#if !TARGET_IPHONE_OS
#import "NSImage+SDCompat.h"

@implementation NSImage (SDCompat)

+ (instancetype)imageWithCGImage:(CGImageRef)imageRef
{
    return [[self alloc] initWithCGImage:imageRef size:NSZeroSize];
}

- (CGFloat)scale
{
    NSInteger width = 0;
    NSInteger height = 0;
    
    for (NSImageRep *representation in self.representations)
    {
        if (representation.pixelsWide * representation.pixelsHigh > width * height)
        {
            width = representation.pixelsWide;
            height = representation.pixelsHigh;
        }
    }
    
    return width / self.size.width;
}

- (NSArray *)images
{
    return nil;
}

@end
#endif
