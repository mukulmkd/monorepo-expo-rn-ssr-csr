#import <Foundation/Foundation.h>

NSBundle* React_SWIFTPM_MODULE_BUNDLE() {
    NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"ReactNativeRuntime_React.bundle"];

    NSBundle *preferredBundle = [NSBundle bundleWithURL:bundleURL];
    if (preferredBundle == nil) {
      return [NSBundle bundleWithPath:@"/Users/mukulkishore/Desktop/Projects/monorepo-expo-rn-ssr-csr/frameworks/ios/ReactNativeRuntime/.build/arm64-apple-macosx/debug/ReactNativeRuntime_React.bundle"];
    }

    return preferredBundle;
}