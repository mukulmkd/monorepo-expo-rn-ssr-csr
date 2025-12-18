#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>

@interface RNSVGCustomFilter : CIFilter {
  CIImage *inputImage1;
}

- (CIColorKernel *)getWithName:(NSString *)name;

@end
