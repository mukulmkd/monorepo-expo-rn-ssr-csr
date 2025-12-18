/**
 * Stub header for RCTImageLoaderProtocol
 * This is a minimal stub to allow native modules to compile.
 * The actual ImageLoader module should be provided by the consuming app.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class RCTImageSource;

typedef void (^RCTImageLoaderCancellationBlock)(void);
typedef void (^RCTImageLoaderCompletionBlock)(NSError *error, UIImage *image);
typedef void (^RCTImageLoaderProgressBlock)(int64_t progress, int64_t total);

@protocol RCTImageLoaderProtocol <NSObject>

- (RCTImageLoaderCancellationBlock)loadImageWithURLRequest:(NSURLRequest *)imageURLRequest
                                                  callback:(RCTImageLoaderCompletionBlock)callback;

- (RCTImageLoaderCancellationBlock)loadImageWithURLRequest:(NSURLRequest *)imageURLRequest
                                                  progress:(RCTImageLoaderProgressBlock)progressBlock
                                                  callback:(RCTImageLoaderCompletionBlock)callback;

@end
