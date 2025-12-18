#import "RNCSafeAreaViewMode.h"
#import <React/Base/RCTConvert.h>

@implementation RCTConvert (RNCSafeAreaView)

RCT_MULTI_ENUM_CONVERTER(
    RNCSafeAreaViewMode,
    (@{
      @"padding" : @(RNCSafeAreaViewModePadding),
      @"margin" : @(RNCSafeAreaViewModeMargin),
    }),
    RNCSafeAreaViewModePadding,
    integerValue);

@end
