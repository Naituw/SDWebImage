/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * Created by james <https://github.com/mystcolor> on 9/28/11.
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDecoder.h"

@implementation UIImage (ForceDecode)

+ (UIImage *)decodedImageWithImage:(UIImage *)image
{
    if ([image sd_isAnimatedGif])
    {
        // Do not decode animated images
        return image;
    }

#if TARGET_IPHONE_OS
    CGImageRef imageRef = image.CGImage;
#else
    CGImageRef imageRef = [image CGImageForProposedRect:NULL context:NULL hints:nil];
#endif
    
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    CGRect imageRect = (CGRect){.origin = CGPointZero, .size = imageSize};

#if TARGET_IPHONE_OS
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
#else
    CGColorSpaceRef colorspace = CGDisplayCopyColorSpace(CGMainDisplayID());
    if (!colorspace) {
        colorspace = CGColorSpaceCreateDeviceRGB();
    }
#endif
    
    if (!colorspace) {
        return image;
    }
    
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);

    int infoMask = (bitmapInfo & kCGBitmapAlphaInfoMask);
    BOOL anyNonAlpha = (infoMask == kCGImageAlphaNone ||
                        infoMask == kCGImageAlphaNoneSkipFirst ||
                        infoMask == kCGImageAlphaNoneSkipLast);

    // CGBitmapContextCreate doesn't support kCGImageAlphaNone with RGB.
    // https://developer.apple.com/library/mac/#qa/qa1037/_index.html
    if (infoMask == kCGImageAlphaNone && CGColorSpaceGetNumberOfComponents(colorspace) > 1)
    {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
       
        // Set noneSkipFirst.
        bitmapInfo |= kCGImageAlphaNoneSkipFirst;
    }
    // Some PNGs tell us they have alpha but only 3 components. Odd.
    else if (!anyNonAlpha && CGColorSpaceGetNumberOfComponents(colorspace) == 3)
    {
        // Unset the old alpha info.
        bitmapInfo &= ~kCGBitmapAlphaInfoMask;
        bitmapInfo |= kCGImageAlphaPremultipliedFirst;
    }

    // It calculates the bytes-per-row based on the bitsPerComponent and width arguments.
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 imageSize.width,
                                                 imageSize.height,
                                                 CGImageGetBitsPerComponent(imageRef),
                                                 0,
                                                 colorspace,
                                                 bitmapInfo);
    CGColorSpaceRelease(colorspace);

    // If failed, return undecompressed image
    if (!context) return image;
	
    CGContextDrawImage(context, imageRect, imageRef);
    CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
	
    CGContextRelease(context);
	
#if TARGET_IPHONE_OS
    UIImage * decompressedImage = [UIImage imageWithCGImage:decompressedImageRef scale:image.scale orientation:image.imageOrientation];
#else
    UIImage * decompressedImage = [UIImage imageWithCGImage:decompressedImageRef];
#endif
    CGImageRelease(decompressedImageRef);
    return decompressedImage;
}

- (BOOL)sd_isAnimatedGif
{
#if TARGET_IPHONE_OS
    return self.images != nil;
#else
    @try {
        NSArray * reps = [self representations];
        for (NSImageRep * rep in reps)
        {
            if ([rep isKindOfClass:[NSBitmapImageRep class]] == YES)
            {
                NSBitmapImageRep * bitmapRep = (NSBitmapImageRep *)rep;
                int numFrame = [[bitmapRep valueForProperty:NSImageFrameCount] intValue];
                return numFrame > 1;
            }
        }
    }@catch (NSException * e) {
    }
    @finally {
    }
    return NO;
#endif
}

@end
