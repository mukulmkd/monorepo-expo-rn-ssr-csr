#import <Foundation/Foundation.h>
#import <React/RCTConvert.h>
#import "RNSVGEdgeMode.h"
#import "RNSVGFilterPrimitive.h"

@interface RNSVGFeGaussianBlur : RNSVGFilterPrimitive

@property (nonatomic, strong) NSString *in1;
@property (nonatomic, strong) NSNumber *stdDeviationX;
@property (nonatomic, strong) NSNumber *stdDeviationY;
@property (nonatomic, assign) RNSVGEdgeMode edgeMode;

@end
