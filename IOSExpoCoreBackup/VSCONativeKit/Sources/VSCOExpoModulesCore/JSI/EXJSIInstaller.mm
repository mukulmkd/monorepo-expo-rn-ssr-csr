#import <Foundation/Foundation.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "EXJSIInstaller.h"
#import "EXJavaScriptRuntime.h"
#import "ExpoModulesHostObject.h"
#if __has_include("BridgelessJSCallInvoker.h")
#import "BridgelessJSCallInvoker.h"
#endif
#import "LazyObject.h"
#import "SharedObject.h"
#import "SharedRef.h"
#import "EventEmitter.h"
#import "NativeModule.h"
#import <objc/message.h>
#import <objc/runtime.h>

namespace jsi = facebook::jsi;

/**
 Property name of the core object in the global scope of the Expo JS runtime.
 */
NSString *const EXGlobalCoreObjectPropertyName = @"expo";

/**
 Property name used to define the modules host object in the main object of the Expo JS runtime.
 */
static NSString *modulesHostObjectPropertyName = @"modules";

@interface RCTBridge (ExpoBridgeWithRuntime)

- (void *)runtime;
- (std::shared_ptr<facebook::react::CallInvoker>)jsCallInvoker;

@end

@implementation EXJavaScriptRuntimeManager

+ (nullable id)runtimeFromBridge:(nonnull RCTBridge *)bridge
{
  jsi::Runtime *jsiRuntime = reinterpret_cast<jsi::Runtime *>(bridge.runtime);
  if (!jsiRuntime) {
    return nil;
  }
  
  // Use dynamic class lookup and objc_msgSend for Swift class
  Class EXRuntimeClass = NSClassFromString(@"EXRuntime");
  if (!EXRuntimeClass) {
    return nil;
  }
  
  // Allocate and initialize in one call
  id allocated = ((id(*)(Class, SEL))objc_msgSend)(EXRuntimeClass, @selector(alloc));
  SEL initSelector = @selector(initWithRuntime:callInvoker:);
  return ((id(*)(id, SEL, jsi::Runtime *, std::shared_ptr<facebook::react::CallInvoker>))objc_msgSend)(allocated, initSelector, jsiRuntime, bridge.jsCallInvoker);
}

#if __has_include(<ReactCommon/RCTRuntimeExecutor.h>) && __has_include("BridgelessJSCallInvoker.h")
+ (nullable id)runtimeFromBridge:(nonnull RCTBridge *)bridge withExecutor:(nonnull RCTRuntimeExecutor *)executor
{
  jsi::Runtime *jsiRuntime = reinterpret_cast<jsi::Runtime *>(bridge.runtime);
  if (!jsiRuntime) {
    return nil;
  }

  // Create a call invoker based on the given runtime executor.
  auto callInvoker = std::make_shared<expo::BridgelessJSCallInvoker>([executor](std::function<void(jsi::Runtime &runtime)> &&callback) {
    // Convert to Objective-C block so it can be captured properly.
    __block auto callbackBlock = callback;

    [executor execute:^(jsi::Runtime &runtime) {
      callbackBlock(runtime);
    }];
  });

  // Use dynamic class lookup and objc_msgSend for Swift class
  Class EXRuntimeClass = NSClassFromString(@"EXRuntime");
  if (!EXRuntimeClass) {
    return nil;
  }
  
  // Allocate and initialize in one call
  id allocated = ((id(*)(Class, SEL))objc_msgSend)(EXRuntimeClass, @selector(alloc));
  SEL initSelector = @selector(initWithRuntime:callInvoker:);
  return ((id(*)(id, SEL, jsi::Runtime *, std::shared_ptr<expo::BridgelessJSCallInvoker>))objc_msgSend)(allocated, initSelector, jsiRuntime, callInvoker);
}
#endif // React Native >=0.74

#pragma mark - Installing JSI bindings

+ (BOOL)installExpoModulesHostObject:(nonnull id)appContext
{
  // Use KVC to get _runtime property from Swift class
  id runtime = [appContext valueForKey:@"_runtime"];

  // The runtime may be unavailable, e.g. remote debugger is enabled or it hasn't been set yet.
  if (!runtime) {
    return NO;
  }

  // Use objc_msgSend for method calls on Swift class
  EXJavaScriptObject *global = ((EXJavaScriptObject *(*)(id, SEL))objc_msgSend)(runtime, @selector(global));
  EXJavaScriptValue *coreProperty = ((EXJavaScriptValue *(*)(id, SEL, NSString *))objc_msgSend)(global, @selector(getProperty:), EXGlobalCoreObjectPropertyName);
  NSAssert([coreProperty isObject], @"The global core property should be an object");
  EXJavaScriptObject *coreObject = [coreProperty getObject];

  if ([coreObject hasProperty:modulesHostObjectPropertyName]) {
    return NO;
  }

  std::shared_ptr<expo::ExpoModulesHostObject> modulesHostObjectPtr = std::make_shared<expo::ExpoModulesHostObject>(appContext);
  EXJavaScriptObject *modulesHostObject = ((EXJavaScriptObject *(*)(id, SEL, std::shared_ptr<expo::ExpoModulesHostObject>))objc_msgSend)(runtime, @selector(createHostObject:), modulesHostObjectPtr);

  // Define the `global.expo.modules` object as a non-configurable, read-only and enumerable property.
  [coreObject defineProperty:modulesHostObjectPropertyName
                       value:modulesHostObject
                     options:EXJavaScriptObjectPropertyDescriptorEnumerable];

  return YES;
}

+ (void)installSharedObjectClass:(nonnull id)runtime releaser:(void(^)(long))releaser
{
  // Use objc_msgSend to call get method on Swift class
  jsi::Runtime *jsiRuntime = ((jsi::Runtime *(*)(id, SEL))objc_msgSend)(runtime, @selector(get));
  expo::SharedObject::installBaseClass(*jsiRuntime, [releaser](expo::SharedObject::ObjectId objectId) {
    releaser(objectId);
  });
}

+ (void)installSharedRefClass:(nonnull id)runtime
{
  // Use objc_msgSend to call get method on Swift class
  jsi::Runtime *jsiRuntime = ((jsi::Runtime *(*)(id, SEL))objc_msgSend)(runtime, @selector(get));
  expo::SharedRef::installBaseClass(*jsiRuntime);
}

+ (void)installEventEmitterClass:(nonnull id)runtime
{
  // Use objc_msgSend to call get method on Swift class
  jsi::Runtime *jsiRuntime = ((jsi::Runtime *(*)(id, SEL))objc_msgSend)(runtime, @selector(get));
  expo::EventEmitter::installClass(*jsiRuntime);
}

+ (void)installNativeModuleClass:(nonnull id)runtime
{
  // Use objc_msgSend to call get method on Swift class
  jsi::Runtime *jsiRuntime = ((jsi::Runtime *(*)(id, SEL))objc_msgSend)(runtime, @selector(get));
  expo::NativeModule::installClass(*jsiRuntime);
}

@end
