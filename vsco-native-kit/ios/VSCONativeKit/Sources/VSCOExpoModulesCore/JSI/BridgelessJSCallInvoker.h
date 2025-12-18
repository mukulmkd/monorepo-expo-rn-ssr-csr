// Copyright 2024-present 650 Industries. All rights reserved.

#pragma once

#ifdef __cplusplus

#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#endif
#if __has_include(<ReactCommon/RuntimeExecutor.h>)
#include <ReactCommon/RuntimeExecutor.h>
#endif

namespace jsi = facebook::jsi;
#if __has_include(<ReactCommon/CallInvoker.h>)
namespace react = facebook::react;
#else
namespace facebook { namespace react { class CallInvoker; class RuntimeExecutor; } }
namespace react = facebook::react;
#endif

namespace expo {

#if __has_include(<ReactCommon/CallInvoker.h>) && __has_include(<ReactCommon/RuntimeExecutor.h>)
class BridgelessJSCallInvoker : public react::CallInvoker {
public:
  explicit BridgelessJSCallInvoker(react::RuntimeExecutor runtimeExecutor) : runtimeExecutor_(std::move(runtimeExecutor)) {}

#if REACT_NATIVE_TARGET_VERSION >= 75
  void invokeAsync(react::CallFunc &&func) noexcept override {
    runtimeExecutor_([func = std::move(func)](jsi::Runtime &runtime) { func(runtime); });
  }

  void invokeSync(react::CallFunc &&func) override {
    throw std::runtime_error("Synchronous native -> JS calls are currently not supported.");
  }
#else
  void invokeAsync(std::function<void()> &&func) noexcept override {
    runtimeExecutor_([func = std::move(func)](jsi::Runtime &runtime) { func(); });
  }

  void invokeSync(std::function<void()> &&func) override {
    throw std::runtime_error("Synchronous native -> JS calls are currently not supported.");
  }
#endif

private:
  react::RuntimeExecutor runtimeExecutor_;

}; // class BridgelessJSCallInvoker
#endif // __has_include(<ReactCommon/CallInvoker.h>) && __has_include(<ReactCommon/RuntimeExecutor.h>)

} // namespace expo

#endif // __cplusplus
