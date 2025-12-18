#import <Foundation/Foundation.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "EXFileSystemInterface.h"

@protocol EXFilePermissionModuleInterface

- (EXFileSystemPermissionFlags)getPathPermissions:(NSString *)path;

@end

