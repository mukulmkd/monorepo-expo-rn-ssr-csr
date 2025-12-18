#import <Foundation/Foundation.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#include <jsi/jsi.h>
#if __has_include(<hermes/hermes.h>)
#import <hermes/hermes.h>
#endif
#if __has_include(<reacthermes/HermesExecutorFactory.h>)
#import <reacthermes/HermesExecutorFactory.h>
#endif

#import "EXJavaScriptRuntime.h"
#import "ExpoModulesHostObject.h"
#import "EXJSIUtils.h"
#import "EXJSIConversions.h"
#import "SharedObject.h"
#import "SharedRef.h"
#import "Swift.h"
#import "TestingJSCallInvoker.h"

// Conditionally include headers that may not be available
#if __has_include(<ReactCommon/TurboModuleUtils.h>)
#import <ReactCommon/TurboModuleUtils.h>
#endif
#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#endif
#if __has_include(<ReactCommon/SchedulerPriority.h>)
#include <ReactCommon/SchedulerPriority.h>
#elif __has_include(<ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>)
#include <ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>
#else
// Fallback: define SchedulerPriority enum if not available
namespace react {
enum class SchedulerPriority : int {
  Immediate = 0,
  UserBlocking = 1,
  Normal = 2,
  Low = 3,
  Idle = 4
};
}
#endif
#if __has_include(<jsc/JSCRuntime.h>)
#include <jsc/JSCRuntime.h>
#endif

@implementation EXJavaScriptRuntime {
  std::shared_ptr<jsi::Runtime> _runtime;
  std::shared_ptr<react::CallInvoker> _jsCallInvoker;
}

/**
 Initializes a runtime that is independent from React Native and its runtime initialization.
 This flow is mostly intended for tests.
 */
- (nonnull instancetype)init
{
  if (self = [super init]) {
#if __has_include(<reacthermes/HermesExecutorFactory.h>)
    _runtime = facebook::hermes::makeHermesRuntime();

    // This version of the Hermes uses a Promise implementation that is provided by the RN.
    // The `setImmediate` function isn't defined, but is required by the Promise implementation.
    // That's why we inject it here.
    auto setImmediatePropName = jsi::PropNameID::forUtf8(*_runtime, "setImmediate");
    _runtime->global().setProperty(
      *_runtime, setImmediatePropName, jsi::Function::createFromHostFunction(*_runtime, setImmediatePropName, 1,
        [](jsi::Runtime &rt, const jsi::Value &thisVal, const jsi::Value *args, size_t count) {
          args[0].asObject(rt).asFunction(rt).call(rt);
          return jsi::Value::undefined();
        })
    );
#else
    // JSC runtime - check if available
    #if __has_include(<jsc/JSCRuntime.h>)
    _runtime = facebook::jsc::makeJSCRuntime();
    #else
    // JSC not available - throw error or use alternative
    @throw [NSException exceptionWithName:@"RuntimeException" reason:@"JSC runtime not available and Hermes not available" userInfo:nil];
    #endif
#endif
    // TestingJSCallInvoker is only available if CallInvoker.h is available
    #if __has_include(<ReactCommon/CallInvoker.h>)
    _jsCallInvoker = std::make_shared<expo::TestingJSCallInvoker>(_runtime);
    #else
    // Cannot create TestingJSCallInvoker without CallInvoker - this is a test-only path anyway
    @throw [NSException exceptionWithName:@"NotSupportedException" reason:@"TestingJSCallInvoker requires CallInvoker.h which is not available" userInfo:nil];
    #endif
  }
  return self;
}

- (nonnull instancetype)initWithRuntime:(nonnull jsi::Runtime *)runtime
                            callInvoker:(std::shared_ptr<react::CallInvoker>)callInvoker
{
  if (self = [super init]) {
    // Creating a shared pointer that points to the runtime but doesn't own it, thus doesn't release it.
    // In this code flow, the runtime should be owned by something else like the RCTBridge.
    // See explanation for constructor (8): https://en.cppreference.com/w/cpp/memory/shared_ptr/shared_ptr
    _runtime = std::shared_ptr<jsi::Runtime>(std::shared_ptr<jsi::Runtime>(), runtime);
    _jsCallInvoker = callInvoker;
  }
  return self;
}

- (nonnull jsi::Runtime *)get
{
  return _runtime.get();
}

- (std::shared_ptr<react::CallInvoker>)callInvoker
{
  return _jsCallInvoker;
}

- (nonnull EXJavaScriptObject *)createObject
{
  auto jsObjectPtr = std::make_shared<jsi::Object>(*_runtime);
  return [[EXJavaScriptObject alloc] initWith:jsObjectPtr runtime:self];
}

- (nonnull EXJavaScriptObject *)createHostObject:(std::shared_ptr<jsi::HostObject>)jsiHostObjectPtr
{
  auto jsObjectPtr = std::make_shared<jsi::Object>(jsi::Object::createFromHostObject(*_runtime, jsiHostObjectPtr));
  return [[EXJavaScriptObject alloc] initWith:jsObjectPtr runtime:self];
}

- (nonnull EXJavaScriptObject *)global
{
  auto jsGlobalPtr = std::make_shared<jsi::Object>(_runtime->global());
  return [[EXJavaScriptObject alloc] initWith:jsGlobalPtr runtime:self];
}

- (nonnull EXJavaScriptObject *)createSyncFunction:(nonnull NSString *)name
                                         argsCount:(NSInteger)argsCount
                                             block:(nonnull JSSyncFunctionBlock)block
{
  JSHostFunctionBlock hostFunctionBlock = ^jsi::Value(
    jsi::Runtime &runtime,
    std::shared_ptr<react::CallInvoker> callInvoker,
    EXJavaScriptValue * _Nonnull thisValue,
    NSArray<EXJavaScriptValue *> * _Nonnull arguments) {
      NSError *error;
      EXJavaScriptValue *result = block(thisValue, arguments, &error);

      if (error == nil) {
        return [result get];
      } else {
        // `expo::makeCodedError` doesn't work during unit tests, so we construct Error and add a code,
        // instead of using the CodedError subclass.
        jsi::String jsCode = expo::convertNSStringToJSIString(runtime, error.userInfo[@"code"]);
        jsi::String jsMessage = expo::convertNSStringToJSIString(runtime, error.userInfo[@"message"]);
        jsi::Value error = runtime
          .global()
          .getProperty(runtime, "Error")
          .asObject(runtime)
          .asFunction(runtime)
          .callAsConstructor(runtime, {
            jsi::Value(runtime, jsMessage)
          });
        error.asObject(runtime).setProperty(runtime, "code", jsi::Value(runtime, jsCode));
        throw jsi::JSError(runtime, jsi::Value(runtime, error));
      }
    };
  return [self createHostFunction:name argsCount:argsCount block:hostFunctionBlock];
}

- (nonnull EXJavaScriptObject *)createAsyncFunction:(nonnull NSString *)name
                                          argsCount:(NSInteger)argsCount
                                              block:(nonnull JSAsyncFunctionBlock)block
{
  JSHostFunctionBlock hostFunctionBlock = ^jsi::Value(
    jsi::Runtime &runtime,
    std::shared_ptr<react::CallInvoker> callInvoker,
    EXJavaScriptValue * _Nonnull thisValue,
    NSArray<EXJavaScriptValue *> * _Nonnull arguments) {
      if (!callInvoker) {
        // In mocked environment the call invoker may be null so it's not supported to call async functions.
        // Testing async functions is a bit more complicated anyway. See `init` description for more.
        throw jsi::JSError(runtime, "Calling async functions is not supported when the call invoker is unavailable");
      }
      // The function that is invoked as a setup of the EXJavaScript `Promise`.
      auto promiseSetup = [callInvoker, block, thisValue, arguments](jsi::Runtime &runtime, std::shared_ptr<react::Promise> promise) {
        expo::callPromiseSetupWithBlock(runtime, callInvoker, promise, ^(RCTPromiseResolveBlock resolver, RCTPromiseRejectBlock rejecter) {
          block(thisValue, arguments, resolver, rejecter);
        });
      };
      // createPromiseAsJSIValue is from TurboModuleUtils
      #if __has_include(<ReactCommon/TurboModuleUtils.h>)
      #import <ReactCommon/TurboModuleUtils.h>
      return createPromiseAsJSIValue(runtime, promiseSetup);
      #else
      // Throw a JSI error (not an NSException) so the message propagates to JS instead of "<unknown>".
      throw jsi::JSError(runtime, "ExpoModulesCore async functions require TurboModuleUtils (createPromiseAsJSIValue) which is not available.");
      #endif
    };
  return [self createHostFunction:name argsCount:argsCount block:hostFunctionBlock];
}

#pragma mark - Classes

typedef jsi::Function (^InstanceFactory)(jsi::Runtime& runtime, NSString * name, expo::common::ClassConstructor constructor);

- (nonnull EXJavaScriptObject *)createInstance:(nonnull NSString *)name
                               instanceFactory:(nonnull InstanceFactory)instanceFactory
                                   constructor:(nonnull ClassConstructorBlock)constructor
{
  expo::common::ClassConstructor jsConstructor = [self, constructor](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    std::shared_ptr<jsi::Object> thisPtr = std::make_shared<jsi::Object>(thisValue.asObject(runtime));
    EXJavaScriptObject *caller = [[EXJavaScriptObject alloc] initWith:thisPtr runtime:self];
    NSArray<EXJavaScriptValue *> *arguments = expo::convertJSIValuesToNSArray(self, args, count);

    // Returning something else than `this` is not supported in native constructors.
    @try {
      constructor(caller, arguments);
    } @catch (NSException *exception) {
      jsi::String jsMessage = expo::convertNSStringToJSIString(runtime, exception.reason ?: @"Constructor failed");
      jsi::Value error = runtime
        .global()
        .getProperty(runtime, "Error")
        .asObject(runtime)
        .asFunction(runtime)
        .callAsConstructor(runtime, {
          jsi::Value(runtime, jsMessage)
        });
      
      if (exception.userInfo[@"code"]) {
        jsi::String jsCode = expo::convertNSStringToJSIString(runtime, exception.userInfo[@"code"]);
        error.asObject(runtime).setProperty(runtime, "code", jsi::Value(runtime, jsCode));
      }
      
      throw jsi::JSError(runtime, jsi::Value(runtime, error));
    }

    return jsi::Value(runtime, thisValue);
  };
  std::shared_ptr<jsi::Function> klass = std::make_shared<jsi::Function>(instanceFactory(*_runtime, name, jsConstructor));
  return [[EXJavaScriptObject alloc] initWith:klass runtime:self];
}

- (nullable EXJavaScriptObject *)createObjectWithPrototype:(nonnull EXJavaScriptObject *)prototype
{
  std::shared_ptr<jsi::Object> object = std::make_shared<jsi::Object>(expo::common::createObjectWithPrototype(*_runtime, [prototype getShared].get()));
  return object ? [[EXJavaScriptObject alloc] initWith:object runtime:self] : nil;
}

#pragma mark - Shared objects

- (nonnull EXJavaScriptObject *)createSharedObjectClass:(nonnull NSString *)name
                                            constructor:(nonnull ClassConstructorBlock)constructor
{
  InstanceFactory instanceFactory = ^(jsi::Runtime& runtime, NSString * name, expo::common::ClassConstructor constructor){
    return expo::SharedObject::createClass(*self->_runtime, [name UTF8String], constructor);
  };
  
  return [self createInstance:name instanceFactory:instanceFactory constructor:constructor];
}

#pragma mark - Shared refs

- (nonnull EXJavaScriptObject *)createSharedRefClass:(nonnull NSString *)name
                                         constructor:(nonnull ClassConstructorBlock)constructor
{
  InstanceFactory instanceFactory = ^(jsi::Runtime& runtime, NSString * name, expo::common::ClassConstructor constructor){
    return expo::SharedRef::createClass(*self->_runtime, [name UTF8String], constructor);
  };
  
  return [self createInstance:name instanceFactory:instanceFactory constructor:constructor];
}

#pragma mark - Script evaluation

- (nonnull EXJavaScriptValue *)evaluateScript:(nonnull NSString *)scriptSource
{
  std::shared_ptr<jsi::StringBuffer> scriptBuffer = std::make_shared<jsi::StringBuffer>([scriptSource UTF8String]);
  jsi::Value result;

  try {
    result = _runtime->evaluateJavaScript(scriptBuffer, "<<evaluated>>");
  } catch (jsi::JSError &error) {
    NSString *reason = [NSString stringWithUTF8String:error.getMessage().c_str()];
    NSString *stack = [NSString stringWithUTF8String:error.getStack().c_str()];

    @throw [NSException exceptionWithName:@"ScriptEvaluationException" reason:reason userInfo:@{
      @"message": reason,
      @"stack": stack,
    }];
  } catch (jsi::JSIException &error) {
    NSString *reason = [NSString stringWithUTF8String:error.what()];

    @throw [NSException exceptionWithName:@"ScriptEvaluationException" reason:reason userInfo:@{
      @"message": reason
    }];
  }
  return [[EXJavaScriptValue alloc] initWithRuntime:self value:std::move(result)];
}

#pragma mark - Runtime execution

- (void)schedule:(nonnull JSRuntimeExecutionBlock)block priority:(int)priority
{
  // CallInvoker needs full definition to call methods - include it here if not already included
  #if !__has_include(<ReactCommon/CallInvoker.h>) && !__has_include(<ReactCommon/TurboModuleUtils.h>)
  // Cannot use CallInvoker methods without full definition
  @throw [NSException exceptionWithName:@"NotSupportedException" reason:@"CallInvoker methods require CallInvoker.h which is not available" userInfo:nil];
  #else
  // Avoid calling the virtual `invokeAsync(CallFunc&&)` directly (vtable/ABI mismatches across distributions can be fatal).
  // RN 0.81.5 provides a non-virtual `invokeAsync(std::function<void()>)` implementation we can call safely.
  (void)priority;
  _jsCallInvoker->invokeAsync([block = std::move(block)]() {
    block();
  });
  #endif
}

#pragma mark - Private

- (nonnull EXJavaScriptObject *)createHostFunction:(nonnull NSString *)name
                                         argsCount:(NSInteger)argsCount
                                             block:(nonnull JSHostFunctionBlock)block
{
  jsi::PropNameID propNameId = jsi::PropNameID::forAscii(*_runtime, [name UTF8String], [name length]);
  std::weak_ptr<react::CallInvoker> weakCallInvoker = _jsCallInvoker;
  jsi::HostFunctionType function = [weakCallInvoker, block, self](jsi::Runtime &runtime, const jsi::Value &thisVal, const jsi::Value *args, size_t count) -> jsi::Value {
    // Theoretically should check here whether the call invoker isn't null, but in mocked environment
    // there is no need to care about that for synchronous calls, so it's ensured in `createAsyncFunction` instead.
    auto callInvoker = weakCallInvoker.lock();
    NSArray<EXJavaScriptValue *> *arguments = expo::convertJSIValuesToNSArray(self, args, count);
    EXJavaScriptValue *thisValue = [[EXJavaScriptValue alloc] initWithRuntime:self value:jsi::Value(runtime, thisVal)];

    return block(runtime, callInvoker, thisValue, arguments);
  };
  std::shared_ptr<jsi::Object> fnPtr = std::make_shared<jsi::Object>(jsi::Function::createFromHostFunction(*_runtime, propNameId, (unsigned int)argsCount, function));
  return [[EXJavaScriptObject alloc] initWith:fnPtr runtime:self];
}

@end
