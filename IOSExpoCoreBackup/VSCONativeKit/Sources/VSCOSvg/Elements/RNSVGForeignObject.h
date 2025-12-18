
#import "RNSVGGroup.h"
#import <React/RCTConvert.h>
#import "RNSVGLength.h"
#import <React/RCTConvert.h>

@interface RNSVGForeignObject : RNSVGGroup

@property (nonatomic, strong) RNSVGLength *x;
@property (nonatomic, strong) RNSVGLength *y;
@property (nonatomic, strong) RNSVGLength *foreignObjectwidth;
@property (nonatomic, strong) RNSVGLength *foreignObjectheight;

@end
