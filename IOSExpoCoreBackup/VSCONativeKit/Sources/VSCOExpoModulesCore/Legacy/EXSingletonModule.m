#import <Foundation/Foundation.h>
// Copyright © 2015 650 Industries. All rights reserved.

#import "Legacy/EXSingletonModule.h"

@implementation EXSingletonModule

+ (const NSString *)name
{
  NSAssert(NO, @"[EXSingletonModule name] method not implemented, you must override it in subclasses.");
  return nil;
}

- (const NSInteger)priority
{
  return 0;
}

@end
