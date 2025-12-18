// Copyright 2022-present 650 Industries. All rights reserved.
// Wrapper header to include JSI headers from ReactCommon
// This is needed because React Native expects <jsi/jsi.h> but it's not directly available
// We include the actual JSI headers from ReactCommon/jsi/jsi/

#ifdef __cplusplus
// Try to include JSI headers through the React product first
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#else
// Fallback: Include JSI headers directly from ReactCommon
// Note: This requires that the React product exposes ReactCommon headers
// The actual JSI headers are in ReactCommon/jsi/jsi/ but there's no main jsi.h
// We need to include the headers that define the JSI types
// Since jsilib.h includes <jsi/jsi.h> which doesn't exist, we can't use it
// Instead, we'll try to include what we need directly
// For now, we'll use a forward declaration approach and include actual headers in .mm files
// This is a workaround until the React product properly exposes JSI headers
#endif

namespace jsi = facebook::jsi;
#endif // __cplusplus

