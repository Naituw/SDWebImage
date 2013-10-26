//
//  UIImage+GIF.m
//  LBGIFImage
//
//  Created by Laurin Brandner on 06.01.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "UIImage+GIF.h"
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

NSString * const NSImageFrameDurationsPropertyKey = @"NSImageFrameDurationsPropertyKey";

@implementation UIImage (GIF)

+ (UIImage *)sd_animatedGIFWithData:(NSData *)data
{
#if TARGET_IPHONE_OS
    if (!data)
    {
        return nil;
    }
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    
    size_t count = CGImageSourceGetCount(source);

    UIImage *animatedImage;

    if (count <= 1)
    {
        animatedImage = [[UIImage alloc] initWithData:data];
    }
    else
    {
        NSMutableArray *images = [NSMutableArray array];

        NSTimeInterval duration = 0.0f;

        for (size_t i = 0; i < count; i++)
        {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);

            NSDictionary *frameProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, i, NULL));
            duration += [[[frameProperties objectForKey:(NSString*)kCGImagePropertyGIFDictionary] objectForKey:(NSString*)kCGImagePropertyGIFDelayTime] doubleValue];

            [images addObject:[UIImage imageWithCGImage:image scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp]];

            CGImageRelease(image);
        }

        if (!duration)
        {
            duration = (1.0f/10.0f)*count;
        }

        animatedImage = [UIImage animatedImageWithImages:images duration:duration];
    }

    CFRelease(source);

    return animatedImage;
#else
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    
    NSImage * image = [[UIImage alloc] initWithData:data];
    
    if (imageSource)
    {
        NSBitmapImageRep * animatableRep = nil;
        
        for (NSImageRep * rep in image.representations)
        {
            if ([rep isKindOfClass:[NSBitmapImageRep class]])
            {
                animatableRep = (NSBitmapImageRep *)rep;
                break;
            }
        }
        
        NSInteger frameCount = [[animatableRep valueForProperty:NSImageFrameCount] integerValue];
        
        if (frameCount > 1)
        {
            NSMutableArray * frameDurations = [NSMutableArray array];
            
            for (NSInteger idx = 0; idx < frameCount; idx++)
            {
                CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, idx, NULL);
                if (!properties) break;
                
                NSDictionary * GIFProperties = [(__bridge NSDictionary *)properties objectForKey:(__bridge NSString *)kCGImagePropertyGIFDictionary];
                
                BOOL stop = YES;
                
                if (GIFProperties)
                {
                    id durationObject = [GIFProperties objectForKey:(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime];
                    if (!durationObject) durationObject = [GIFProperties objectForKey:(__bridge NSString *)kCGImagePropertyGIFDelayTime];
                    
                    if ([durationObject doubleValue])
                    {
                        [frameDurations addObject:durationObject];
                        stop = NO;
                    }
                }
                
                CFRelease(properties);
                
                if (stop)
                {
                    break;
                }
            }
            
            if (frameDurations.count == (NSUInteger)frameCount)
            {
                objc_setAssociatedObject(image, (__bridge CFStringRef)NSImageFrameDurationsPropertyKey, frameDurations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        
        CFRelease(imageSource);
    }
    
    return image;
#endif
}

+ (UIImage *)sd_animatedGIFNamed:(NSString *)name
{
#if TARGET_IPHONE_OS
    CGFloat scale = [UIScreen mainScreen].scale;
    
    if (scale > 1.0f)
    {
        NSString *retinaPath = [[NSBundle mainBundle] pathForResource:[name stringByAppendingString:@"@2x"] ofType:@"gif"];
        
        NSData *data = [NSData dataWithContentsOfFile:retinaPath];
        
        if (data)
        {
            return [UIImage sd_animatedGIFWithData:data];
        }
        
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"gif"];
        
        data = [NSData dataWithContentsOfFile:path];
        
        if (data)
        {
            return [UIImage sd_animatedGIFWithData:data];
        }
        
        return [UIImage imageNamed:name];
    }
    else
    {
        NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"gif"];
        
        NSData *data = [NSData dataWithContentsOfFile:path];
        
        if (data)
        {
            return [UIImage sd_animatedGIFWithData:data];
        }
        
        return [UIImage imageNamed:name];
    }
#else
    return [UIImage imageNamed:name];
#endif
}

- (UIImage *)sd_animatedImageByScalingAndCroppingToSize:(CGSize)size
{
#if TARGET_IPHONE_OS
    if (CGSizeEqualToSize(self.size, size) || CGSizeEqualToSize(size, CGSizeZero))
    {
        return self;
    }
    
    CGSize scaledSize = size;
	CGPoint thumbnailPoint = CGPointZero;
    
    CGFloat widthFactor = size.width / self.size.width;
    CGFloat heightFactor = size.height / self.size.height;
    CGFloat scaleFactor = (widthFactor > heightFactor) ? widthFactor :heightFactor;
    scaledSize.width = self.size.width * scaleFactor;
    scaledSize.height = self.size.height * scaleFactor;
    
    if (widthFactor > heightFactor)
    {
        thumbnailPoint.y = (size.height - scaledSize.height) * 0.5; 
    }
    else if (widthFactor < heightFactor)
    {
        thumbnailPoint.x = (size.width - scaledSize.width) * 0.5;
    }
    
    NSMutableArray *scaledImages = [NSMutableArray array];
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0); 
    
    for (UIImage *image in self.images)
    {
        [image drawInRect:CGRectMake(thumbnailPoint.x, thumbnailPoint.y, scaledSize.width, scaledSize.height)];
        UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
        
        [scaledImages addObject:newImage];
    }
    
    UIGraphicsEndImageContext();
	
	return [UIImage animatedImageWithImages:scaledImages duration:self.duration];
#else
    return self;
#endif
}

@end
