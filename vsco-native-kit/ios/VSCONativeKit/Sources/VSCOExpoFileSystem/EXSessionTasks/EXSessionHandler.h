// Copyright 2015-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>
#import "Platform/Platform.h"
#import "Legacy/EXSingletonModule.h"

NS_ASSUME_NONNULL_BEGIN

@protocol EXSessionHandler

- (void)invokeCompletionHandlerForSessionIdentifier:(NSString *)identifier;

@end

@interface EXSessionHandler : EXSingletonModule <UIApplicationDelegate, EXSessionHandler>

@end

NS_ASSUME_NONNULL_END
