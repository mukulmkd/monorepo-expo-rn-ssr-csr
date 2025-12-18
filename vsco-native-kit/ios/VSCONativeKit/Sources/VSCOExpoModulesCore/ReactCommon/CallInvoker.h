// Shim header for React Native's ReactCommon/CallInvoker.h.
// Some distributions used in this repo don't expose the full ReactCommon headers publicly,
// but ExpoModulesCore needs the CallInvoker type for scheduling work on the JS thread.
//
// If the real header exists later in the include search paths, prefer it.
#pragma once

#if __has_include_next(<ReactCommon/CallInvoker.h>)
#include_next <ReactCommon/CallInvoker.h>
#else

#ifdef __cplusplus

#include <functional>

// SchedulerPriority is part of RN callinvoker. Include it at global scope (NOT inside namespaces),
// otherwise its internal `namespace facebook::react { ... }` gets nested and breaks symbol lookup.
#if __has_include(<ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>)
#include <ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>
#endif

namespace facebook {
namespace jsi {
class Runtime;
} // namespace jsi
namespace react {

// RN 0.81+ CallInvoker API uses CallFunc = std::function<void(jsi::Runtime&)>
using CallFunc = std::function<void(::facebook::jsi::Runtime &)>;

/**
 * NOTE: This shim must match the ABI of the React Native runtime that ships in VSCOReactNativeRuntime.
 * RN 0.81.5 exports (non-virtual) overloads:
 * - CallInvoker::invokeAsync(std::function<void()>)
 * - CallInvoker::invokeSync(std::function<void()>)
 * and an overload:
 * - CallInvoker::invokeAsync(SchedulerPriority, CallFunc)
 * alongside the core virtual methods:
 * - invokeAsync(CallFunc)
 * - invokeSync(CallFunc)
 */
class CallInvoker {
public:
  virtual ~CallInvoker() = default;

  // Core virtual interface implemented by JSCallInvoker, RuntimeSchedulerCallInvoker, etc.
  virtual void invokeAsync(CallFunc &&func) noexcept = 0;
  virtual void invokeSync(CallFunc &&func) = 0;

  // Priority-aware overload provided by RN. Keep it NON-virtual to avoid vtable/ABI mismatch.
#if __has_include(<ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>)
  void invokeAsync(::facebook::react::SchedulerPriority priority, CallFunc &&func) noexcept;
#endif

  // Convenience overloads implemented in RN (operate on std::function<void()>).
  void invokeAsync(std::function<void(void)> &&func) noexcept;
  void invokeSync(std::function<void(void)> &&func);
};

} // namespace react
} // namespace facebook

#endif // __cplusplus

#endif


