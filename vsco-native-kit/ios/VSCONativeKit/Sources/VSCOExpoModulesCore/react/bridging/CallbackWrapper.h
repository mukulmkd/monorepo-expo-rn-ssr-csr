/*
 * Minimal declaration shim for React Native's <react/bridging/CallbackWrapper.h>.
 *
 * VSCOReactNativeRuntime (RN 0.81.5) exports `facebook::react::CallbackWrapper::createWeak(...)`
 * in the binary, but doesn't ship the public header. We provide a compatible declaration so that
 * ExpoModulesCore can compile and link against the real implementation in the RN runtime.
 */

#pragma once

#ifdef __cplusplus

// JSI header location differs depending on distribution.
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include("jsi/jsi.h")
#include "jsi/jsi.h"
#else
#include "JSI/jsi/jsi.h"
#endif

#include <memory>

// CallInvoker header location also differs; ExpoModulesCore provides a shim at <ReactCommon/CallInvoker.h>.
#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#endif

namespace facebook::react {

class CallbackWrapper {
public:
  static std::weak_ptr<CallbackWrapper> createWeak(
    facebook::jsi::Function &&callback,
    facebook::jsi::Runtime &runtime,
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker
  );

  virtual ~CallbackWrapper() = default;

  virtual facebook::jsi::Function &callback() = 0;
  virtual facebook::jsi::Runtime &runtime() = 0;
  virtual std::shared_ptr<facebook::react::CallInvoker> &jsInvoker() = 0;
  virtual void destroy() = 0;
};

} // namespace facebook::react

#endif // __cplusplus


