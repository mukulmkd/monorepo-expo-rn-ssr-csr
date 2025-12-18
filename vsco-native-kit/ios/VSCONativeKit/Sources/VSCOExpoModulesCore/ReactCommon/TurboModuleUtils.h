// Shim header for React Native's TurboModuleUtils.
// Some React Native distributions (like VSCOReactNativeRuntime) don't ship `ReactCommon/TurboModuleUtils.h`
// in the public headers. ExpoModulesCore's JSI bridge uses `createPromiseAsJSIValue`, so we provide a
// declaration shim that links against the real implementation shipped in the React Native runtime binary.
//
// If the real header exists later in the include search paths, we prefer it.
//
// This file is Objective-C++/C++ only.
#pragma once

#if __has_include_next(<ReactCommon/TurboModuleUtils.h>)
// Prefer the real RN header if it exists.
#include_next <ReactCommon/TurboModuleUtils.h>
#else

#ifdef __cplusplus
// JSI header location differs depending on distribution.
// Prefer standard include if available, otherwise fall back to vendored headers in VSCOExpoModulesCore.
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include("jsi/jsi.h")
#include "jsi/jsi.h"
#else
#include "JSI/jsi/jsi.h"
#endif

#include <memory>
#include <functional>
#include <string>

namespace facebook {
namespace react {

// Forward declare CallInvoker to match RN signature surface.
class CallInvoker;

// RN 0.81.5 exports a `facebook::react::Promise` class (not just a struct).
class Promise {
public:
  Promise(facebook::jsi::Runtime &runtime, facebook::jsi::Function resolve, facebook::jsi::Function reject);
  virtual ~Promise();

  void resolve(facebook::jsi::Value const &value);
  void reject(std::string const &message);
};

/**
 * Declares the RN helper exported from the runtime binary.
 * Mangled symbol (RN 0.81.5): facebook::react::createPromiseAsJSIValue(jsi::Runtime&, std::function<void(jsi::Runtime&, std::shared_ptr<Promise>)>&&)
 */
facebook::jsi::Value createPromiseAsJSIValue(
  facebook::jsi::Runtime &runtime,
  std::function<void(facebook::jsi::Runtime &, std::shared_ptr<facebook::react::Promise>)> &&promiseSetup
);

} // namespace react
} // namespace facebook

// ExpoModulesCore calls `createPromiseAsJSIValue(...)` unqualified in ObjC++ files.
using facebook::react::createPromiseAsJSIValue;

#endif // __cplusplus

#endif


