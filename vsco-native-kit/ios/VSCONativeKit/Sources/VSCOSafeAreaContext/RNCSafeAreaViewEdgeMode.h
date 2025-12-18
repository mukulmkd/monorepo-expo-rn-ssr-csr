#import <Foundation/Foundation.h>
#import <React/Base/RCTConvert.h>

typedef NS_ENUM(NSInteger, RNCSafeAreaViewEdgeMode) {
  RNCSafeAreaViewEdgeModeOff,
  RNCSafeAreaViewEdgeModeAdditive,
  RNCSafeAreaViewEdgeModeMaximum
};

@interface RCTConvert (RNCSafeAreaViewEdgeMode)
+ (RNCSafeAreaViewEdgeMode)RNCSafeAreaViewEdgeMode:(nullable id)json;
@end
