#import <Foundation/Foundation.h>
#import "CoreModuleHelper.h"

#ifdef EXPO_MODULES_CORE_VERSION
#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define EXPO_MODULES_CORE_VERSION_STRING STRINGIZE2(EXPO_MODULES_CORE_VERSION)
#endif

@implementation CoreModuleHelper

+ (NSString *)getVersion {
#ifdef EXPO_MODULES_CORE_VERSION_STRING
  return @EXPO_MODULES_CORE_VERSION_STRING;
#else
  // Fallback if version macro is not defined
  return @"0.0.0";
#endif
}

@end
