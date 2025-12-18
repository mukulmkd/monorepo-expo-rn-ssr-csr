// Copyright 2018-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#import "Legacy/Protocols/EXInternalModule.h"
#import "Interfaces/Permissions/EXUserNotificationCenterProxyInterface.h"

@interface EXReactNativeUserNotificationCenterProxy : NSObject <EXInternalModule, EXUserNotificationCenterProxyInterface>

@end
