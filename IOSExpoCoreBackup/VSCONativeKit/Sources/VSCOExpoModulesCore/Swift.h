// Copyright 2018-present 650 Industries. All rights reserved.

// The generated swift header may depend on some Objective-C declarations,
// adding dependency imports here to prevent declarations not found errors.
#import "EXDefines.h"
#import "JSI/EXJavaScriptObject.h"
#import "JSI/EXJavaScriptRuntime.h"
#import "RCTComponentData+Privates.h"

// When `use_frameworks!` is used, the generated Swift header is inside VSCOExpoModulesCore module.
// Otherwise, it's available only locally with double-quoted imports.
// Note: The Swift header is generated during build, so we use __has_include to check if it exists
// However, for Objective-C files that need Swift classes, we need to ensure the header is imported
// even if it doesn't exist yet (it will be generated during the build)
#if __has_include(<VSCOExpoModulesCore/VSCOExpoModulesCore-Swift.h>)
#import <VSCOExpoModulesCore/VSCOExpoModulesCore-Swift.h>
#elif __has_include("VSCOExpoModulesCore-Swift.h")
#import "VSCOExpoModulesCore-Swift.h"
#else
// Swift header not generated yet - forward declare EXAppContext for now
// The actual definition will be available once the Swift target builds
@class EXAppContext;
#endif
