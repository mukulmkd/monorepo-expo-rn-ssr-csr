#import <UIKit/UIKit.h>
// Copyright 2015-present 650 Industries. All rights reserved.

#import "Platform/Platform.h"

@protocol EXUtilitiesInterface

- (nullable NSDictionary *)launchOptions;

- (nullable UIViewController *)currentViewController;

@end
