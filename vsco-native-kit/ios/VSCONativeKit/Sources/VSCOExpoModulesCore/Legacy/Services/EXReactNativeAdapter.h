#import <Foundation/Foundation.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "Legacy/Protocols/EXUIManager.h"
#import "Legacy/Protocols/EXInternalModule.h"
#import "Legacy/Protocols/EXAppLifecycleService.h"
#import "Legacy/Protocols/EXAppLifecycleListener.h"
#import "Legacy/Protocols/EXModuleRegistryConsumer.h"
#import "Legacy/Protocols/EXJavaScriptContextProvider.h"
#import "Legacy/EXBridgeModule.h"

@interface EXReactNativeAdapter : NSObject <EXInternalModule, EXBridgeModule, EXAppLifecycleService, EXUIManager, EXJavaScriptContextProvider, EXModuleRegistryConsumer>

- (void)setBridge:(RCTBridge *)bridge;

@end
