#import "LFGlassView.h"
#import "LFDisplayBridge.h"

@interface LFGlassView () <LFDisplayBridgeTriggering>

@property (nonatomic, assign, readonly) CGSize bufferSize;

@property (nonatomic, assign, readonly) CGContextRef effectInContext;
@property (nonatomic, assign, readonly) CGContextRef effectOutContext;

@property (nonatomic, assign, readonly) vImage_Buffer effectInBuffer;
@property (nonatomic, assign, readonly) vImage_Buffer effectOutBuffer;

@property (nonatomic, assign, readonly) uint32_t precalculatedBlurKernel;

- (void) updatePrecalculatedBlurKernel;
- (CGSize) scaledSize;
- (void) recreateImageBuffers;

@end

@implementation LFGlassView

- (id) initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		[self setup];
	}
	return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
	if (self = [super initWithCoder:aDecoder]) {
		[self setup];
	}
	return self;
}

- (void) setup {
	self.clipsToBounds = YES;
	self.layer.cornerRadius = 20.0f;
	self.blurRadius = 4.0f;
	self.scaleFactor = 0.25f;
	self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	self.opaque = NO;
	self.userInteractionEnabled = NO;
}

- (void) dealloc {
	if (_effectInContext) {
		CGContextRelease(_effectInContext);
	}
	if (_effectOutContext) {
		CGContextRelease(_effectOutContext);
	}
}

- (void) willMoveToSuperview:(UIView*)superview {
	if (superview) {
		[[LFDisplayBridge sharedInstance] addSubscribedViewsObject:self];
	} else {
		[[LFDisplayBridge sharedInstance] removeSubscribedViewsObject:self];
	}
}

- (void) setBlurRadius:(CGFloat)blurRadius {
	if (blurRadius == _blurRadius) {
		return;
	}
	[self willChangeValueForKey:@"blurRadius"];
	
	_blurRadius = blurRadius;
	[self updatePrecalculatedBlurKernel];
	
	[self didChangeValueForKey:@"blurRadius"];
}

- (void) updatePrecalculatedBlurKernel {
	uint32_t radius = (uint32_t)floor(_blurRadius * 3. * sqrt(2 * M_PI) / 4 + 0.5);
	radius += (radius + 1) % 2;
	_precalculatedBlurKernel = radius;
}

- (void) setScaleFactor:(CGFloat)scaleFactor
{
	if (scaleFactor == _scaleFactor) {
		return;
	}
	[self willChangeValueForKey:@"scaleFactor"];
	
	_scaleFactor = scaleFactor;
	
	CGSize scaledSize = [self scaledSize];
	
	if (!CGSizeEqualToSize(_bufferSize, scaledSize)) {
		_bufferSize = scaledSize;
		[self recreateImageBuffers];
	}
	
	[self didChangeValueForKey:@"scaleFactor"];
}

- (CGSize) scaledSize {
	CGSize scaledSize = (CGSize){
		_scaleFactor * CGRectGetWidth(self.bounds),
		_scaleFactor * CGRectGetHeight(self.bounds)
	};
	return scaledSize;
}

- (void) layoutSubviews {
	[super layoutSubviews];
	
	CGSize scaledSize = [self scaledSize];
	
	if (!CGSizeEqualToSize(_bufferSize, scaledSize)) {
		_bufferSize = scaledSize;
		[self recreateImageBuffers];
	}
}

- (void) recreateImageBuffers {
	CGRect visibleRect = self.frame;
	CGSize bufferSize = _bufferSize;
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	
	CGContextRef effectInContext = CGBitmapContextCreate(NULL, bufferSize.width, bufferSize.height, 8, bufferSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGContextRef effectOutContext = CGBitmapContextCreate(NULL, bufferSize.width, bufferSize.height, 8, bufferSize.width * 8, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	
	CGColorSpaceRelease(colorSpace);
	
	CGContextConcatCTM(effectInContext, (CGAffineTransform){
		.a = 1,
		.b = 0,
		.c = 0,
		.d = -1,
		.tx = 0,
		.ty = bufferSize.height
	});
	CGContextScaleCTM(effectInContext, _scaleFactor, _scaleFactor);
	CGContextTranslateCTM(effectInContext, -visibleRect.origin.x, -visibleRect.origin.y);
	
	CGContextRef prevEffectInContext = _effectInContext;
	if (prevEffectInContext) {
		CGContextRelease(prevEffectInContext);
	}
	_effectInContext = effectInContext;
	
	CGContextRef prevEffectOutContext = _effectOutContext;
	if (prevEffectOutContext) {
		CGContextRelease(prevEffectOutContext);
	}
	_effectOutContext = effectOutContext;
	
	vImage_Buffer effectInBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectInContext),
		.width = CGBitmapContextGetWidth(effectInContext),
		.height = CGBitmapContextGetHeight(effectInContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectInContext)
	};
	
	_effectInBuffer = effectInBuffer;
	
	vImage_Buffer effectOutBuffer = (vImage_Buffer){
		.data = CGBitmapContextGetData(effectOutContext),
		.width = CGBitmapContextGetWidth(effectOutContext),
		.height = CGBitmapContextGetHeight(effectOutContext),
		.rowBytes = CGBitmapContextGetBytesPerRow(effectOutContext)
	};
	
	_effectOutBuffer = effectOutBuffer;
}

- (void) refresh {
	CGContextRef effectInContext = _effectInContext;
	CGContextRef effectOutContext = _effectOutContext;
	vImage_Buffer effectInBuffer = _effectInBuffer;
	vImage_Buffer effectOutBuffer = _effectOutBuffer;
	
	self.hidden = YES;
	if (!self.superview) {
		return;
	}
	[self.superview.layer renderInContext:effectInContext];
	self.hidden = NO;
	
	uint32_t blurKernel = _precalculatedBlurKernel;
	
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectOutBuffer, &effectInBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	vImageBoxConvolve_ARGB8888(&effectInBuffer, &effectOutBuffer, NULL, 0, 0, blurKernel, blurKernel, 0, kvImageEdgeExtend);
	
	CGImageRef outImage = CGBitmapContextCreateImage(effectOutContext);
	
	self.layer.contents = (__bridge id)(outImage);
	CGImageRelease(outImage);
}

@end