// Copyright 2022-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>

#ifdef __cplusplus
// JSI headers should be available through the React product
// Since we use std::shared_ptr<jsi::Object>, we need the complete type, not just forward declarations
// Try to include JSI headers - we have a wrapper at JSI/jsi/jsi.h that redirects to ReactCommon headers
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include("jsi/jsi.h")
// Try local path (relative to this file)
#include "jsi/jsi.h"
#elif __has_include(<ReactCommon/jsi/jsi/jsilib.h>)
// Fallback: try ReactCommon path directly
#include <ReactCommon/jsi/jsi/jsilib.h>
#else
// Last resort: forward declarations (won't work for std::shared_ptr but will compile)
// The .mm files will need to include the actual headers
namespace facebook {
namespace jsi {
    class Runtime;
    class Object;
    class Value;
    class String;
    class Function;
    class PropNameID;
    class HostObject;
    class HostFunction;
    template<typename T> class HostObjectType;
    template<typename R, typename... Args> class HostFunctionType;
}
}
#endif
namespace jsi = facebook::jsi;
#endif // __cplusplus

@class EXJavaScriptRuntime;
@class EXJavaScriptValue;
@class EXJavaScriptWeakObject;

/**
 The property descriptor options for the property being defined or modified.
 */
typedef NS_OPTIONS(NSInteger, EXJavaScriptObjectPropertyDescriptor) {
  /**
   If set, the type of this property descriptor may be changed and if the property may be deleted from the corresponding object.
   */
  EXJavaScriptObjectPropertyDescriptorConfigurable = 1 << 0,
  /**
   If set, the property shows up during enumeration of the properties on the corresponding object.
   */
  EXJavaScriptObjectPropertyDescriptorEnumerable = 1 << 1,
  /**
   If set, the value associated with the property may be changed with an assignment operator.
   */
  EXJavaScriptObjectPropertyDescriptorWritable = 1 << 2,
} NS_SWIFT_NAME(JavaScriptObjectPropertyDescriptor);

NS_SWIFT_NAME(JavaScriptObject)
@interface EXJavaScriptObject : NSObject

// Some parts of the interface must be hidden for Swift – it can't import any C++ code.
#ifdef __cplusplus
- (nonnull instancetype)initWith:(std::shared_ptr<jsi::Object>)jsObjectPtr
                         runtime:(nonnull EXJavaScriptRuntime *)runtime;

/**
 Returns the pointer to the underlying object.
 */
- (nonnull jsi::Object *)get;

/**
 Returns the shared pointer to the underlying object.
 */
- (std::shared_ptr<jsi::Object>)getShared;
#endif // __cplusplus

#pragma mark - Accessing object properties

/**
 \return a bool whether the object has a property with the given name.
 */
- (BOOL)hasProperty:(nonnull NSString *)name;

/**
 \return the property of the object with the given name.
 If the name isn't a property on the object, returns the `undefined` value.
 */
- (nonnull EXJavaScriptValue *)getProperty:(nonnull NSString *)name;

/**
 \return an array consisting of all enumerable property names in the object and its prototype chain.
 */
- (nonnull NSArray<NSString *> *)getPropertyNames;

#pragma mark - Modifying object properties

/**
 Sets the value for the property with the given name.
 */
- (void)setProperty:(nonnull NSString *)name value:(nullable id)value;

/**
 Defines a new property or modifies an existing property on the object using the property descriptor.
 */
- (void)defineProperty:(nonnull NSString *)name descriptor:(nonnull EXJavaScriptObject *)descriptor;

/**
 Defines a new property or modifies an existing property on the object. Calls `Object.defineProperty` under the hood.
 */
- (void)defineProperty:(nonnull NSString *)name value:(nullable id)value options:(EXJavaScriptObjectPropertyDescriptor)options;

#pragma mark - WeakObject

- (nonnull EXJavaScriptWeakObject *)createWeak;

#pragma mark - Deallocator

- (void)setObjectDeallocator:(void (^ _Nonnull)(void))deallocatorBlock;

#pragma mark - Memory pressure

/**
 Sets the memory pressure to inform the GC about how much external memory is associated with that specific JS object.
 */
- (void)setExternalMemoryPressure:(size_t)size;

@end
