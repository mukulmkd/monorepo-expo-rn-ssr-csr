#import <Foundation/Foundation.h>
#import <objc/message.h>
// Copyright 2024-present 650 Industries. All rights reserved.

#if __has_include(<ReactCommon/RCTTurboModule.h>)
#import <ReactCommon/RCTTurboModule.h>
#endif
#import "ExpoBridgeModule.h"
#import "EXJSIInstaller.h"

// The runtime executor is included as of React Native 0.74 in bridgeless mode.
#if __has_include(<ReactCommon/RCTRuntimeExecutor.h>)
#import <ReactCommon/RCTRuntimeExecutor.h>
#endif // React Native >=0.74

@implementation ExpoBridgeModule

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE(ExpoModulesCore);

- (instancetype)init
{
  if (self = [super init]) {
    // Dynamically create EXAppContext instance using objc_msgSend
    Class appContextClass = NSClassFromString(@"EXAppContext");
    if (appContextClass) {
      _appContext = ((id(*)(Class, SEL))objc_msgSend)(appContextClass, @selector(alloc));
      _appContext = ((id(*)(id, SEL))objc_msgSend)(_appContext, @selector(init));
    }
  }
  return self;
}

- (instancetype)initWithAppContext:(id) appContext
{
  if (self = [super init]) {
    _appContext = appContext;
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  // We do want to run the initialization (`setBridge`) on the JS thread.
  return NO;
}

- (void)setBridge:(RCTBridge *)bridge
{
  // As of React Native 0.74 with the New Architecture enabled,
  // it's actually an instance of `RCTBridgeProxy` that provides backwards compatibility.
  // Also, hold on with initializing the runtime until `setRuntimeExecutor` is called.
  _bridge = bridge;
  
  // Set reactBridge property dynamically
  if (_appContext) {
    ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setReactBridge:), bridge);
  }

#if !__has_include(<ReactCommon/RCTRuntimeExecutor.h>)
  // Set _runtime property dynamically (the property is _runtime but the setter is setRuntime:)
  if (_appContext) {
    id runtime = [EXJavaScriptRuntimeManager runtimeFromBridge:bridge];
    // Try setRuntime: first (standard setter for _runtime property)
    if ([_appContext respondsToSelector:@selector(setRuntime:)]) {
      ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setRuntime:), runtime);
    } else {
      // Fallback: try setting _runtime directly via KVC
      [_appContext setValue:runtime forKey:@"_runtime"];
    }
  }
#endif // React Native <0.74
}

#if __has_include(<ReactCommon/RCTRuntimeExecutor.h>)
- (void)setRuntimeExecutor:(RCTRuntimeExecutor *)runtimeExecutor
{
  // Set _runtime property dynamically
  if (_appContext) {
    id runtime = [EXJavaScriptRuntimeManager runtimeFromBridge:_bridge withExecutor:runtimeExecutor];
    // Try setRuntime: first (standard setter for _runtime property)
    if ([_appContext respondsToSelector:@selector(setRuntime:)]) {
      ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setRuntime:), runtime);
    } else {
      // Fallback: try setting _runtime directly via KVC
      [_appContext setValue:runtime forKey:@"_runtime"];
    }
  }
}
#endif // React Native >=0.74

/**
 This should be called inside `[EXNativeModulesProxy setBridge:]`.
 */
- (void)legacyProxyDidSetBridge:(nonnull EXNativeModulesProxy *)moduleProxy
           legacyModuleRegistry:(nonnull EXModuleRegistry *)moduleRegistry
{
  if (!_appContext) return;
  
  // Set properties dynamically
  ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setLegacyModulesProxy:), moduleProxy);
  ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setLegacyModuleRegistry:), moduleRegistry);

  // We need to register all the modules after the legacy module registry is set
  // otherwise legacy modules (e.g. permissions) won't be available in OnCreate { }
  ((void(*)(id, SEL, NSString *))objc_msgSend)(_appContext, @selector(useModulesProvider:), @"ExpoModulesProvider");
}

/**
 A synchronous method that is called from JS before requiring
 any module to ensure that all necessary bindings are installed.
 */
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(installModules)
{
  if (_bridge && _appContext) {
    // Check if _runtime is nil by getting it dynamically
    // The getter for _runtime property is runtime (without underscore)
    id runtime = nil;
    if ([_appContext respondsToSelector:@selector(runtime)]) {
      runtime = ((id(*)(id, SEL))objc_msgSend)(_appContext, @selector(runtime));
    } else {
      // Fallback: try getting _runtime directly via KVC
      runtime = [_appContext valueForKey:@"_runtime"];
    }
    
    if (!runtime) {
      // TODO: Keep this condition until we remove the other way of installing modules.
      // See `setBridge` method above.
      runtime = [EXJavaScriptRuntimeManager runtimeFromBridge:_bridge];
      // Try setRuntime: first
      if ([_appContext respondsToSelector:@selector(setRuntime:)]) {
        ((void(*)(id, SEL, id))objc_msgSend)(_appContext, @selector(setRuntime:), runtime);
      } else {
        // Fallback: try setting _runtime directly via KVC
        [_appContext setValue:runtime forKey:@"_runtime"];
      }
    }
  }
  return nil;
}

@end
