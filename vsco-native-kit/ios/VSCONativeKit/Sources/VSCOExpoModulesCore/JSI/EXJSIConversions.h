// Copyright 2018-present 650 Industries. All rights reserved.

#ifdef __cplusplus

#import <Foundation/Foundation.h>

#include <jsi/jsi.h>

#import <React/RCTBridgeModule.h>
#ifdef __cplusplus
#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
namespace react = facebook::react;
#else
namespace facebook { namespace react { class CallInvoker; } }
namespace react = facebook::react;
#endif
using namespace facebook;
#endif

@class EXJavaScriptValue;
@class EXJavaScriptRuntime;

namespace expo
{

    jsi::Value convertNSNumberToJSIBoolean(jsi::Runtime &runtime, NSNumber *value);

    jsi::Value convertNSNumberToJSINumber(jsi::Runtime &runtime, NSNumber *value);

    jsi::String convertNSStringToJSIString(jsi::Runtime &runtime, NSString *value);

    jsi::String convertNSURLToJSIString(jsi::Runtime &runtime, NSURL *value);

    jsi::Object convertNSDictionaryToJSIObject(jsi::Runtime &runtime, NSDictionary *value);

    jsi::Array convertNSArrayToJSIArray(jsi::Runtime &runtime, NSArray *value);

    std::vector<jsi::Value> convertNSArrayToStdVector(jsi::Runtime &runtime, NSArray *value);

    jsi::Value convertObjCObjectToJSIValue(jsi::Runtime &runtime, id value);

    NSString *convertJSIStringToNSString(jsi::Runtime &runtime, const jsi::String &value);

    NSArray *convertJSIArrayToNSArray(jsi::Runtime &runtime, const jsi::Array &value, std::shared_ptr<react::CallInvoker> jsInvoker);

    NSArray<EXJavaScriptValue *> *convertJSIValuesToNSArray(EXJavaScriptRuntime *runtime, const jsi::Value *values, size_t count);

    NSDictionary *convertJSIObjectToNSDictionary(jsi::Runtime &runtime, const jsi::Object &value, std::shared_ptr<react::CallInvoker> jsInvoker);

    id convertJSIValueToObjCObject(jsi::Runtime &runtime, const jsi::Value &value, std::shared_ptr<react::CallInvoker> jsInvoker);

    RCTResponseSenderBlock convertJSIFunctionToCallback(jsi::Runtime &runtime, const jsi::Function &value, std::shared_ptr<react::CallInvoker> jsInvoker);

} // namespace expo

#endif
