// Copyright © 2018 650 Industries. All rights reserved.

#import "EXFaceDetectorManagerInterface.h"

@protocol EXFaceDetectorManagerProviderInterface

- (id<EXFaceDetectorManagerInterface>)createFaceDetectorManager;

@end
