#import <Foundation/Foundation.h>
// Copyright 2024-present 650 Industries. All rights reserved.

@protocol RCTBridgeModule;

#import "Legacy/NativeModulesProxy/EXNativeModulesProxy.h"
#import "Legacy/ModuleRegistry/EXModuleRegistry.h"

// Use id instead of EXAppContext to avoid needing the Swift class definition
// EXAppContext is a Swift class (@objc(EXAppContext)) that will be available at runtime

@interface ExpoBridgeModule : NSObject <RCTBridgeModule>

@property(nonatomic, nullable, strong) id appContext;

- (nonnull instancetype)initWithAppContext:(nonnull id)appContext;

- (void)legacyProxyDidSetBridge:(nonnull EXNativeModulesProxy *)moduleProxy
           legacyModuleRegistry:(nonnull EXModuleRegistry *)moduleRegistry;

@end
