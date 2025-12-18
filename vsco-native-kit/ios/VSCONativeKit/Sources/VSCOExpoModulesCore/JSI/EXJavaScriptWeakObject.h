// Copyright 2022-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>
#import "EXJavaScriptValue.h"
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

NS_SWIFT_NAME(JavaScriptWeakObject)
@interface EXJavaScriptWeakObject : NSObject

#ifdef __cplusplus
- (nonnull instancetype)initWith:(std::shared_ptr<jsi::Object>)jsObject
                         runtime:(nonnull EXJavaScriptRuntime *)runtime;
#endif // __cplusplus

- (nullable EXJavaScriptObject *)lock;

@end
