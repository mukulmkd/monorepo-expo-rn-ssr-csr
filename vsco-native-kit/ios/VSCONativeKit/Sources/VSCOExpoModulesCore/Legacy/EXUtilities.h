#import <UIKit/UIKit.h>
// Copyright © 2018 650 Industries. All rights reserved.



#import "Platform/Platform.h"
#import "Legacy/Protocols/EXInternalModule.h"
#import "Legacy/Protocols/EXUtilitiesInterface.h"
#import "Legacy/Protocols/EXModuleRegistryConsumer.h"

NS_ASSUME_NONNULL_BEGIN

@interface EXUtilities : NSObject <EXInternalModule, EXUtilitiesInterface, EXModuleRegistryConsumer>

+ (void)performSynchronouslyOnMainThread:(nonnull void (^)(void))block;
+ (CGFloat)screenScale;
+ (nullable UIColor *)UIColor:(nullable id)json;
+ (nullable NSDate *)NSDate:(nullable id)json;
+ (nonnull NSString *)hexStringWithCGColor:(nonnull CGColorRef)color;

- (nullable UIViewController *)currentViewController;
- (nullable NSDictionary *)launchOptions;

+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error;

@end

NS_ASSUME_NONNULL_END
