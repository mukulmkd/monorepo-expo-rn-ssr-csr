// Copyright 2015-present 650 Industries. All rights reserved.

#pragma once

#ifdef __cplusplus

#include <jsi/jsi.h>

// TestingJSCallInvoker requires full CallInvoker definition (inherits from it)
// If CallInvoker.h is not available, this class cannot be used
#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
namespace react = facebook::react;
#else
// Cannot use TestingJSCallInvoker without CallInvoker - forward declare only
namespace facebook { namespace react { class CallInvoker; } }
namespace react = facebook::react;
// Note: TestingJSCallInvoker class definition will be skipped if CallInvoker is incomplete
#endif

#include "MainThreadInvoker.h"

namespace jsi = facebook::jsi;

namespace expo {

/**
 * Dummy CallInvoker.
 * Async functions are invoked on the main thread on iOS.
 * Used in the test environment to check the async flow.
 */
#if __has_include(<ReactCommon/CallInvoker.h>)
class TestingJSCallInvoker : public react::CallInvoker {
public:
  explicit TestingJSCallInvoker(const std::shared_ptr<jsi::Runtime>& runtime) : runtime(runtime) {}

  void invokeAsync(react::CallFunc &&func) noexcept override {
    auto weakRuntime = runtime;
    std::function<void()> mainThreadFunc = [weakRuntime, func]() {
      auto strongRuntime = weakRuntime.lock();
      func(*strongRuntime);
    };
    MainThreadInvoker::invokeOnMainThread(mainThreadFunc);
  }

  void invokeSync(react::CallFunc &&func) override {
    func(*runtime.lock());
  }

  ~TestingJSCallInvoker() override = default;

  std::weak_ptr<jsi::Runtime> runtime;
};
#endif // __has_include(<ReactCommon/CallInvoker.h>)

} // namespace expo

#endif // __cplusplus
