#import "RNSVGBrush.h"
#import <React/RCTConvert.h>
#import "RNSVGFilterPrimitive.h"
#import <React/RCTConvert.h>

@interface RNSVGFeFlood : RNSVGFilterPrimitive

@property (nonatomic, strong) RNSVGBrush *floodColor;
@property (nonatomic, assign) CGFloat floodOpacity;

@end
