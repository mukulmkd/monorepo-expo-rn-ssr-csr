#import <UIKit/UIKit.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "Platform/Platform.h"

NS_ASSUME_NONNULL_BEGIN

// Use id instead of EXReactDelegate to avoid needing the Swift class definition
// EXReactDelegate is a Swift class (@objc(EXReactDelegate)) that will be available at runtime

/**
 A wrapper of `ExpoReactDelegate` for Objective-C bindings.
 */
@interface EXReactDelegateWrapper : NSObject

- (instancetype)initWithExpoReactDelegate:(id)expoReactDelegate;

- (UIView *)createReactRootView:(NSString *)moduleName
              initialProperties:(nullable NSDictionary *)initialProperties
                  launchOptions:(nullable NSDictionary *)launchOptions;

- (NSURL *)bundleURL;

- (UIViewController *)createRootViewController;

@end

NS_ASSUME_NONNULL_END
