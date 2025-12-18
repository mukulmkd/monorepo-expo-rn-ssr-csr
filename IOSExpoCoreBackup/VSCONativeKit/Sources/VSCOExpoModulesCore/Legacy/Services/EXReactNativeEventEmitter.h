// Copyright 2018-present 650 Industries. All rights reserved.

#import <React/RCTEventEmitter.h>

#import "Legacy/Protocols/EXInternalModule.h"
#import "Legacy/Protocols/EXEventEmitterService.h"
#import "Legacy/Protocols/EXModuleRegistryConsumer.h"
#import "Legacy/EXBridgeModule.h"

// Swift compatibility headers (e.g. `ExpoModulesCore-Swift.h`) are not available in headers,
// so we use class forward declaration here. Swift header must be imported in the `.m` file.
// Since EXAppContext is a Swift class and the Swift header may not be available in ObjC target,
// we use id and runtime methods in the implementation.
@class EXAppContext;

@interface EXReactNativeEventEmitter : RCTEventEmitter <EXInternalModule, EXBridgeModule, EXModuleRegistryConsumer, EXEventEmitterService>

@property(nonatomic, strong) id appContext;

@end
