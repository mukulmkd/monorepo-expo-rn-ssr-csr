#import "RNCSafeAreaViewEdgeMode.h"
#import <React/Base/RCTConvert.h>

@implementation RCTConvert (RNCSafeAreaViewEdgeMode)

RCT_ENUM_CONVERTER(
    RNCSafeAreaViewEdgeMode,
    (@{
      @"off" : @(RNCSafeAreaViewEdgeModeOff),
      @"additive" : @(RNCSafeAreaViewEdgeModeAdditive),
      @"maximum" : @(RNCSafeAreaViewEdgeModeMaximum),
    }),
    RNCSafeAreaViewEdgeModeOff,
    integerValue);

@end
