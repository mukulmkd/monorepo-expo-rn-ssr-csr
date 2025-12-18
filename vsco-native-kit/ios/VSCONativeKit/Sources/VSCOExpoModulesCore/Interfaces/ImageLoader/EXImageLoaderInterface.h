#import <UIKit/UIKit.h>
// Copyright © 2018 650 Industries. All rights reserved.

#import "Platform/Platform.h"

typedef void (^EXImageLoaderCompletionBlock)(NSError *error, UIImage *image);

@protocol EXImageLoaderInterface <NSObject>

- (void)loadImageForURL:(NSURL *)imageURL
      completionHandler:(EXImageLoaderCompletionBlock)completionHandler;

@end
