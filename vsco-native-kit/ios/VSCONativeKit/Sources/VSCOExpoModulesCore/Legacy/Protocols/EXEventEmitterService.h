// Copyright © 2018 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>

#import "EXDefines.h"
#import "Legacy/EXExportedModule.h"

@protocol EXEventEmitterService

- (void)sendEventWithName:(NSString *)name body:(id)body;

@end
