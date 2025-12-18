#import <Foundation/Foundation.h>
// Copyright 2022-present 650 Industries. All rights reserved.

#import <sstream>

#import "EXJSIConversions.h"
#import "EXJSIUtils.h"
#import "JSIUtils.h"
#import "NativeModule.h"
#import "EventEmitter.h"

// Include CallbackWrapper if available.
// RN header path differs across distributions; VSCOReactNativeRuntime ships it under ReactCommon/...
#if __has_include(<react/bridging/CallbackWrapper.h>)
#import <react/bridging/CallbackWrapper.h>
#elif __has_include(<ReactCommon/react/nativemodule/core/ReactCommon/CallbackWrapper.h>)
#import <ReactCommon/react/nativemodule/core/ReactCommon/CallbackWrapper.h>
#endif

namespace expo {

void callPromiseSetupWithBlock(jsi::Runtime &runtime, std::shared_ptr<react::CallInvoker> jsInvoker, std::shared_ptr<react::Promise> promise, PromiseInvocationBlock setupBlock)
{
#if __has_include(<ReactCommon/TurboModuleUtils.h>)
  __block BOOL isSettled = NO;

  RCTPromiseResolveBlock resolveBlock = ^(id result) {
    if (isSettled) {
      return;
    }
    if (!jsInvoker || !promise) {
      return;
    }

    // Retain ObjC object across async boundary.
    auto retainedResult = std::shared_ptr<void>((__bridge_retained void *)result, [](void *p) {
      if (p) { CFRelease(p); }
    });

    // Use RN's non-virtual priority overload to avoid direct virtual dispatch.
    jsInvoker->invokeAsync(::facebook::react::SchedulerPriority::NormalPriority, [promise, retainedResult](jsi::Runtime &rt) {
      @autoreleasepool {
        id obj = (__bridge id)retainedResult.get();
        jsi::Value arg = convertObjCObjectToJSIValue(rt, obj);
        promise->resolve(arg);
      }
    });

    isSettled = YES;
  };

  RCTPromiseRejectBlock rejectBlock = ^(NSString *code, NSString *message, NSError *error) {
    if (isSettled) {
      return;
    }
    if (!jsInvoker || !promise) {
      return;
    }

    NSString *finalMessage = message ?: @"Unknown error";
    if (code.length > 0) {
      finalMessage = [NSString stringWithFormat:@"%@: %@", code, finalMessage];
    }
    if (error) {
      finalMessage = [NSString stringWithFormat:@"%@ (%@)", finalMessage, error.localizedDescription];
    }
    std::string msg([finalMessage UTF8String] ?: "");

    // Use RN's non-virtual priority overload to avoid direct virtual dispatch.
    jsInvoker->invokeAsync(::facebook::react::SchedulerPriority::NormalPriority, [promise, msg = std::move(msg)](jsi::Runtime &) mutable {
      promise->reject(msg);
    });

    isSettled = YES;
  };

  setupBlock(resolveBlock, rejectBlock);
#else
  throw jsi::JSError(runtime, "ExpoModulesCore async functions require TurboModuleUtils (createPromiseAsJSIValue/Promise) which is not available.");
#endif
}

#pragma mark - Weak objects

bool isWeakRefSupported(jsi::Runtime &runtime) {
  return runtime.global().hasProperty(runtime, "WeakRef");
}

std::shared_ptr<jsi::Object> createWeakRef(jsi::Runtime &runtime, std::shared_ptr<jsi::Object> object) {
  jsi::Object weakRef = runtime
    .global()
    .getProperty(runtime, "WeakRef")
    .asObject(runtime)
    .asFunction(runtime)
    .callAsConstructor(runtime, jsi::Value(runtime, *object))
    .asObject(runtime);
  return std::make_shared<jsi::Object>(std::move(weakRef));
}

std::shared_ptr<jsi::Object> derefWeakRef(jsi::Runtime &runtime, std::shared_ptr<jsi::Object> object) {
  jsi::Value ref = object->getProperty(runtime, "deref")
    .asObject(runtime)
    .asFunction(runtime)
    .callWithThis(runtime, *object);

  if (ref.isUndefined()) {
    return nullptr;
  }
  return std::make_shared<jsi::Object>(ref.asObject(runtime));
}

#pragma mark - Errors

jsi::Value makeCodedError(jsi::Runtime &runtime, NSString *code, NSString *message) {
  jsi::String jsCode = convertNSStringToJSIString(runtime, code);
  jsi::String jsMessage = convertNSStringToJSIString(runtime, message);

  return runtime
    .global()
    .getProperty(runtime, "ExpoModulesCore_CodedError")
    .asObject(runtime)
    .asFunction(runtime)
    .callAsConstructor(runtime, {
      jsi::Value(runtime, jsCode),
      jsi::Value(runtime, jsMessage)
    });
}

} // namespace expo

@implementation EXJSIUtils

+ (nonnull EXJavaScriptObject *)createNativeModuleObject:(nonnull EXJavaScriptRuntime *)runtime
{
  std::shared_ptr<jsi::Object> nativeModule = std::make_shared<jsi::Object>(expo::NativeModule::createInstance(*[runtime get]));
  return [[EXJavaScriptObject alloc] initWith:nativeModule runtime:runtime];
}

+ (void)emitEvent:(nonnull NSString *)eventName
         toObject:(nonnull EXJavaScriptObject *)object
    withArguments:(nonnull NSArray<id> *)arguments
        inRuntime:(nonnull EXJavaScriptRuntime *)runtime
{
  const std::vector<jsi::Value> argumentsVector(expo::convertNSArrayToStdVector(*[runtime get], arguments));
  expo::EventEmitter::emitEvent(*[runtime get], *[object get], [eventName UTF8String], std::move(argumentsVector));
}

@end
