#import <Foundation/Foundation.h>

NSBundle* ReactNativeRuntime_SWIFTPM_MODULE_BUNDLE() {
    NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"ReactNativeRuntime_ReactNativeRuntime.bundle"];

    NSBundle *preferredBundle = [NSBundle bundleWithURL:bundleURL];
    if (preferredBundle == nil) {
      return [NSBundle bundleWithPath:@"/Users/mukulkishore/Desktop/Projects/monorepo-expo-rn-ssr-csr/frameworks/ios/ReactNativeRuntime/.build/arm64-apple-macosx/debug/ReactNativeRuntime_ReactNativeRuntime.bundle"];
    }

    return preferredBundle;
}