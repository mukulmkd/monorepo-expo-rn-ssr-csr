#import <UIKit/UIKit.h>
#import <objc/message.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "EXReactDelegateWrapper.h"

@interface EXReactDelegateWrapper()

@property (nonatomic, weak) id expoReactDelegate;

@end

@implementation EXReactDelegateWrapper

- (instancetype)initWithExpoReactDelegate:(id)expoReactDelegate
{
  if (self = [super init]) {
    _expoReactDelegate = expoReactDelegate;
  }
  return self;
}

- (UIView *)createReactRootView:(NSString *)moduleName
              initialProperties:(nullable NSDictionary *)initialProperties
                  launchOptions:(nullable NSDictionary *)launchOptions
{
  // Since EXReactDelegate methods are marked @objc, we can call them directly on id
  // The compiler allows this because @objc methods are available via message sending
  // We use a cast to suppress the warning about unknown selector
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wobjc-method-access"
  return ((UIView *(*)(id, SEL, NSString *, NSDictionary *, NSDictionary *))objc_msgSend)(
    _expoReactDelegate,
    @selector(createReactRootViewWithModuleName:initialProperties:launchOptions:),
    moduleName,
    initialProperties,
    launchOptions
  );
  #pragma clang diagnostic pop
}

- (NSURL *)bundleURL
{
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wobjc-method-access"
  return ((NSURL *(*)(id, SEL))objc_msgSend)(_expoReactDelegate, @selector(bundleURL));
  #pragma clang diagnostic pop
}

- (UIViewController *)createRootViewController
{
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wobjc-method-access"
  return ((UIViewController *(*)(id, SEL))objc_msgSend)(_expoReactDelegate, @selector(createRootViewController));
  #pragma clang diagnostic pop
}

@end
