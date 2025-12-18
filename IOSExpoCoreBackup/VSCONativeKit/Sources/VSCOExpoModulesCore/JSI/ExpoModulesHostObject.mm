#import <Foundation/Foundation.h>
#import <objc/message.h>
// Copyright 2022-present 650 Industries. All rights reserved.

#import "ExpoModulesHostObject.h"
#import "EXJavaScriptObject.h"
#import "LazyObject.h"

namespace expo {

ExpoModulesHostObject::ExpoModulesHostObject(id appContext) : appContext(appContext) {}

ExpoModulesHostObject::~ExpoModulesHostObject() {
  modulesCache.clear();
  // Set _runtime to nil using KVC
  if (appContext) {
    [appContext setValue:nil forKey:@"_runtime"];
  }
}

jsi::Value ExpoModulesHostObject::get(jsi::Runtime &runtime, const jsi::PropNameID &name) {
  std::string moduleName = name.utf8(runtime);
  NSString *nsModuleName = [NSString stringWithUTF8String:moduleName.c_str()];

  // Call hasModule: dynamically
  BOOL hasModule = NO;
  if (appContext && [appContext respondsToSelector:@selector(hasModule:)]) {
    hasModule = ((BOOL(*)(id, SEL, NSString *))objc_msgSend)(appContext, @selector(hasModule:), nsModuleName);
  }
  
  if (!hasModule) {
    // The module object can already be cached but no longer registered — we remove it from the cache in that case.
    modulesCache.erase(moduleName);
    return jsi::Value::undefined();
  }
  if (UniqueJSIObject &cachedObject = modulesCache[moduleName]) {
    return jsi::Value(runtime, *cachedObject);
  }

  // Create a lazy object for the specific module. It defers initialization of the final module object.
  LazyObject::Shared moduleLazyObject = std::make_shared<LazyObject>(^SharedJSIObject(jsi::Runtime &runtime) {
    // Call getNativeModuleObject: dynamically
    id nativeModuleObject = nil;
    if (appContext && [appContext respondsToSelector:@selector(getNativeModuleObject:)]) {
      nativeModuleObject = ((id(*)(id, SEL, NSString *))objc_msgSend)(appContext, @selector(getNativeModuleObject:), nsModuleName);
    }
    if (nativeModuleObject && [nativeModuleObject respondsToSelector:@selector(getShared)]) {
      return ((SharedJSIObject(*)(id, SEL))objc_msgSend)(nativeModuleObject, @selector(getShared));
    }
    return nullptr;
  });

  // Save the module's lazy host object for later use.
  modulesCache[moduleName] = std::make_unique<jsi::Object>(jsi::Object::createFromHostObject(runtime, moduleLazyObject));

  return jsi::Value(runtime, *modulesCache[moduleName]);
}

void ExpoModulesHostObject::set(jsi::Runtime &runtime, const jsi::PropNameID &name, const jsi::Value &value) {
  std::string message("RuntimeError: Cannot override the host object for expo module '");
  message += name.utf8(runtime);
  message += "'.";
  throw jsi::JSError(runtime, message);
}

std::vector<jsi::PropNameID> ExpoModulesHostObject::getPropertyNames(jsi::Runtime &runtime) {
  NSArray<NSString *> *moduleNames = nil;
  // Call getModuleNames dynamically
  if (appContext && [appContext respondsToSelector:@selector(getModuleNames)]) {
    moduleNames = ((NSArray<NSString *> *(*)(id, SEL))objc_msgSend)(appContext, @selector(getModuleNames));
  }
  
  std::vector<jsi::PropNameID> propertyNames;
  
  if (moduleNames) {
    propertyNames.reserve([moduleNames count]);

    for (NSString *moduleName in moduleNames) {
      propertyNames.push_back(jsi::PropNameID::forAscii(runtime, [moduleName UTF8String]));
    }
  }
  return propertyNames;
}

} // namespace expo
