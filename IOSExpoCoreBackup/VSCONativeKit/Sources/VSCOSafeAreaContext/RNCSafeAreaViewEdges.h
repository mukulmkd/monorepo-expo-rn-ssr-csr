#import <Foundation/Foundation.h>
#import <React/Base/RCTConvert.h>
#import "RNCSafeAreaViewEdgeMode.h"

typedef struct RNCSafeAreaViewEdges {
  RNCSafeAreaViewEdgeMode top;
  RNCSafeAreaViewEdgeMode right;
  RNCSafeAreaViewEdgeMode bottom;
  RNCSafeAreaViewEdgeMode left;
} RNCSafeAreaViewEdges;

RNCSafeAreaViewEdges RNCSafeAreaViewEdgesMake(
    RNCSafeAreaViewEdgeMode top,
    RNCSafeAreaViewEdgeMode right,
    RNCSafeAreaViewEdgeMode bottom,
    RNCSafeAreaViewEdgeMode left);
