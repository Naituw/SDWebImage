/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "UIImage+GIF.h"
#import <objc/message.h>

@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (copy, nonatomic) void (^cancelBlock)();
@property (strong, nonatomic) NSOperation *cacheOperation;
@property (retain, nonatomic) NSString * imageURL;

@end

@interface SDWebImageManager ()

@property (strong, nonatomic, readwrite) SDImageCache *imageCache;
@property (strong, nonatomic, readwrite) SDWebImageDownloader *imageDownloader;
@property (strong, nonatomic) NSMutableArray *failedURLs;
@property (strong, nonatomic) NSMutableArray *runningOperations;

@end

@implementation SDWebImageManager

+ (id)sharedManager
{
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{instance = self.new;});
    return instance;
}

- (id)init
{
    if ((self = [super init]))
    {
        _imageCache = [self createCache];
        _imageDownloader = [self createDownloader];
        _failedURLs = NSMutableArray.new;
        _runningOperations = NSMutableArray.new;
    }
    return self;
}

- (SDImageCache *)createCache
{
    return [SDImageCache sharedImageCache];
}

- (SDWebImageDownloader *)createDownloader
{
    return [SDWebImageDownloader sharedDownloader];
}

- (NSString *)cacheKeyForURL:(NSURL *)url
{
    return [self cacheKeyForURL:url stylerKey:nil];
}
- (NSString *)cacheKeyForURL:(NSURL *)url stylerKey:(NSString *)stylerKey
{
    if (self.cacheKeyFilter)
    {
        return self.cacheKeyFilter(url);
    }
    else if (!stylerKey)
    {
        return [url absoluteString];
    }
    else
    {
        return [NSString stringWithFormat:@"%@_sd_styler_%@", [url absoluteString], stylerKey];
    }
}

- (BOOL)diskImageExistsForURL:(NSURL *)url
{
    NSString *key = [self cacheKeyForURL:url];
    return [self.imageCache diskImageExistsWithKey:key];
}

- (id<SDWebImageOperation>)downloadWithURL:(NSURL *)url options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedWithFinishedBlock)completedBlock
{
    return [self downloadWithURL:url operationClass:nil options:options progress:progressBlock completed:completedBlock];
}

- (id<SDWebImageOperation>)downloadWithURL:(NSURL *)url operationClass:(Class)operationClass options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedWithFinishedBlock)completedBlock
{
    return [self downloadWithURL:url operationClass:nil options:options progress:progressBlock styler:NULL stylerKey:nil completed:completedBlock];
}

- (id<SDWebImageOperation>)downloadWithURL:(NSURL *)url options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock styler:(UIImage * (^)(UIImage *))styler stylerKey:(NSString *)stylerKey completed:(SDWebImageCompletedWithFinishedBlock)completedBlock
{
    return [self downloadWithURL:url operationClass:nil options:options progress:progressBlock styler:styler stylerKey:stylerKey completed:completedBlock];
}

- (id<SDWebImageOperation>)downloadWithURL:(NSURL *)url operationClass:(Class)operationClass options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock styler:(UIImage * (^)(UIImage *))styler stylerKey:(NSString *)stylerKey completed:(SDWebImageCompletedWithFinishedBlock)completedBlock
{
    // Invoking this method without a completedBlock is pointless
    NSParameterAssert(completedBlock);
    
    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, XCode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    if ([url isKindOfClass:NSString.class])
    {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    if (![url isKindOfClass:NSURL.class])
    {
        url = nil;
    }

    __block SDWebImageCombinedOperation *operation = SDWebImageCombinedOperation.new;
    __weak SDWebImageCombinedOperation *weakOperation = operation;
    
    operation.imageURL = url.absoluteString;
    
    BOOL isFailedUrl = NO;
    @synchronized(self.failedURLs)
    {
        isFailedUrl = [self.failedURLs containsObject:url];
    }

    if (!url || (!(options & SDWebImageRetryFailed) && isFailedUrl))
    {
        dispatch_main_sync_safe(^
        {
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil];
                completedBlock(nil, error, SDImageCacheTypeNone, YES);
        });
        return operation;
    }

    @synchronized(self.runningOperations)
    {
        [self.runningOperations addObject:operation];
    }
    NSString *key = [self cacheKeyForURL:url stylerKey:stylerKey];

    operation.cacheOperation = [self.imageCache queryDiskCacheForKey:key done:^(UIImage *image, SDImageCacheType cacheType)
    {
        if (operation.isCancelled)
        {
            @synchronized(self.runningOperations)
            {
                [self.runningOperations removeObject:operation];
            }

            return;
        }

        if ((!image || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url]))
        {
            if (image && options & SDWebImageRefreshCached)
            {
                dispatch_main_sync_safe(^
                {
                    // If image was found in the cache bug SDWebImageRefreshCached is provided, notify about the cached image
                    // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                    completedBlock(image, nil, cacheType, YES);
                });
            }

            // download if no image or requested to refresh anyway, and download allowed by delegate
            SDWebImageDownloaderOptions downloaderOptions = 0;
            if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (image && options & SDWebImageRefreshCached)
            {
                // force progressive off if image already cached but forced refreshing
                downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // ignore image read from NSURLCache if image if cached but force refreshing
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            id<SDWebImageOperation> subOperation = [self.imageDownloader downloadImageWithURL:url operationClass:operationClass options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *data, NSError *error, BOOL finished)
            {                
                if (weakOperation.isCancelled)
                {
                    dispatch_main_sync_safe(^
                    {
                        completedBlock(nil, nil, SDImageCacheTypeNone, finished);
                    });
                }
                else if (error)
                {
                    dispatch_main_sync_safe(^
                    {
                        completedBlock(nil, error, SDImageCacheTypeNone, finished);
                    });

                    if (error.code != NSURLErrorNotConnectedToInternet)
                    {
                        @synchronized(self.failedURLs)
                        {
                            [self.failedURLs addObject:url];
                        }
                    }
                }
                else
                {
                    BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);

                    if (options & SDWebImageRefreshCached && image && !downloadedImage)
                    {
                        // Image refresh hit the NSURLCache cache, do not call the completion block
                    }
                    else if (downloadedImage && stylerKey)
                    {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            
                            UIImage *transformedImage = downloadedImage;
                            NSData *dataToStore = data;
                            
                            if (styler)
                            {
                                transformedImage = styler(downloadedImage);
                                
                                if (![transformedImage isEqual:image])
                                {
#if TARGET_IPHONE_OS
                                    dataToStore = UIImagePNGRepresentation(transformedImage);
#else
                                    CGImageRef CGImage = [transformedImage CGImageForProposedRect:NULL context:NULL hints:nil];
                                    NSMutableData * imageData = [NSMutableData data];
                                    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, (CFStringRef)kUTTypePNG, 1, NULL);
                                    NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:@(1.0), kCGImageDestinationLossyCompressionQuality, nil];
                                    CGImageDestinationAddImage(destination, CGImage, (__bridge CFDictionaryRef)properties);
                                    CGImageDestinationFinalize(destination);
                                    CFRelease(destination);
                                    dataToStore = imageData;
#endif
                                }
                            }
                            
                            dispatch_main_sync_safe(^{
                                completedBlock(transformedImage, nil, SDImageCacheTypeNone, finished);
                            });
                            
                            if (transformedImage && finished)
                            {
                                [self.imageCache storeImage:transformedImage imageData:dataToStore forKey:key toDisk:cacheOnDisk];
                            }
                        });

                    }
                    // NOTE: We don't call transformDownloadedImage delegate method on animated images as most transformation code would mangle it
                    else if (downloadedImage && !downloadedImage.images && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)])
                    {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^
                        {
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];

                            dispatch_main_sync_safe(^
                            {
                                completedBlock(transformedImage, nil, SDImageCacheTypeNone, finished);
                            });

                            if (transformedImage && finished)
                            {
                                NSData *dataToStore = [transformedImage isEqual:downloadedImage] ? data : nil;
                                [self.imageCache storeImage:transformedImage imageData:dataToStore forKey:key toDisk:cacheOnDisk];
                            }
                        });
                    }
                    else
                    {
                        dispatch_main_sync_safe(^
                        {
                            completedBlock(downloadedImage, nil, SDImageCacheTypeNone, finished);
                        });

                        if (downloadedImage && finished)
                        {
                            [self.imageCache storeImage:downloadedImage imageData:data forKey:key toDisk:cacheOnDisk];
                        }
                    }
                }

                if (finished)
                {
                    @synchronized(self.runningOperations)
                    {
                        [self.runningOperations removeObject:operation];
                    }
                }
            }];
            operation.cancelBlock = ^{[subOperation cancel];};
        }
        else if (image)
        {
            dispatch_main_sync_safe(^
            {
                completedBlock(image, nil, cacheType, YES);
            });
            @synchronized(self.runningOperations)
            {
                [self.runningOperations removeObject:operation];
            }
        }
        else
        {
            // Image not in cache and download disallowed by delegate
            dispatch_main_sync_safe(^
            {
                completedBlock(nil, nil, SDImageCacheTypeNone, YES);
            });
            @synchronized(self.runningOperations)
            {
                [self.runningOperations removeObject:operation];
            }
        }
    }];

    return operation;
}

- (void)cancelAll
{
    @synchronized(self.runningOperations)
    {
        [self.runningOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeAllObjects];
    }
}

- (void)cancelOperationWithImageURL:(NSString *)url
{
    @synchronized(self.runningOperations)
    {
        NSMutableIndexSet * indexes = [NSMutableIndexSet indexSet];
        
        [self.runningOperations enumerateObjectsUsingBlock:^(id<SDWebImageOperation> obj, NSUInteger idx, BOOL *stop) {
            if ([[obj imageURL] isEqual:url])
            {
                [obj cancel];
                [indexes addIndex:idx];
            }
        }];
        
        [self.runningOperations removeObjectsAtIndexes:indexes];
    }
}

- (BOOL)isRunning
{
    return self.runningOperations.count > 0;
}

@end

@implementation SDWebImageCombinedOperation

- (void)setCancelBlock:(void (^)())cancelBlock
{
    if (self.isCancelled)
    {
        if (cancelBlock) cancelBlock();
    }
    else
    {
        _cancelBlock = [cancelBlock copy];
    }
}

- (void)cancel
{
    self.cancelled = YES;
    if (self.cacheOperation)
    {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.cancelBlock)
    {
        self.cancelBlock();
        self.cancelBlock = nil;
    }
}

@end
