#import <Foundation/Foundation.h>
#import <React/RCTConvert.h>
#import "RNSVGFilterPrimitive.h"

@interface RNSVGFeOffset : RNSVGFilterPrimitive

@property (nonatomic, strong) NSString *in1;
@property (nonatomic, strong) RNSVGLength *dx;
@property (nonatomic, strong) RNSVGLength *dy;

@end
