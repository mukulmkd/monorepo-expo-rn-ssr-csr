// Copyright 2023-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>
#import "EXJavaScriptRuntime.h"

#ifdef __cplusplus
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include(<ReactCommon/jsi/jsi/jsilib.h>)
#include <ReactCommon/jsi/jsi/jsilib.h>
#else
#include <ReactCommon/jsi/jsi/jsilib.h>
#endif

namespace jsi = facebook::jsi;
#endif // __cplusplus

NS_SWIFT_NAME(RawJavaScriptFunction)
@interface EXRawJavaScriptFunction : NSObject

#ifdef __cplusplus
- (nonnull instancetype)initWith:(std::shared_ptr<jsi::Function>)function
                         runtime:(nonnull EXJavaScriptRuntime *)runtime;
#endif // __cplusplus

- (nonnull EXJavaScriptValue *)callWithArguments:(nonnull NSArray<id> *)arguments
                                      thisObject:(nullable EXJavaScriptObject *)thisObject
                                   asConstructor:(BOOL)asConstructor;

@end
