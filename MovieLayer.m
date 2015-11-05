/*

File: MovieLayer.h

Abstract: Custom LKOpenGLLayer that renders a QT movie through a visual context

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
Computer, Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Computer,
Inc. may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright © 2006 Apple Computer, Inc., All Rights Reserved

*/ 
#import "MovieLayer.h"

@interface MovieLayer (internal)
- (void)_invalidate;
@end

@implementation MovieLayer

//--------------------------------------------------------------------------------------------------

+ (MovieLayer *)layerWithMovie:(QTMovie *)movie
{
	MovieLayer		*layer;
	NSSize			sz;
	NSValue			*value;

	layer = [self layer];

	if (movie != nil)
	{
		value = [movie attributeForKey:QTMovieNaturalSizeAttribute];
		sz = [value sizeValue];

		[layer setMovie:movie];
		[layer setBounds:CGRectMake (0, 0, sz.width, sz.height)];		//set the layer to be of the size of the movie
	}

	return layer;
}

//--------------------------------------------------------------------------------------------------

- (void)dealloc
{
	[self _invalidate];
	[super dealloc];
}

//--------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------

- (BOOL)asynchronous
{
	return [self movie] != nil ? YES : NO;
}

//--------------------------------------------------------------------------------------------------

- (void)_invalidate
{
	QTMovie *m;

	if (visualContext != NULL)
	{
		// setup the movie's visual context
		m = [self movie];
		if (m != nil)
			SetMovieVisualContext([m quickTimeMovie], NULL);

		QTVisualContextRelease(visualContext);
		visualContext = NULL;
	}

	if (currentFrame != NULL)
	{
		CVOpenGLTextureRelease(currentFrame);
		currentFrame = NULL;
	}

	layer_cgl_ctx = NULL;
}

//--------------------------------------------------------------------------------------------------

- (void)willChangeValueForKey:(NSString *)key
{
	if ([key isEqualToString:@"movie"])
	{
		[self _invalidate];
		[self setNeedsDisplay];
	}

	[super willChangeValueForKey:key];
}

//--------------------------------------------------------------------------------------------------

- (bool)canDrawInCGLContext:(CGLContextObj)cgl_ctx
    pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t
    displayTime:(const CVTimeStamp *)ts
{
	NSDictionary		*dict;

	if (layer_cgl_ctx != NULL && layer_cgl_ctx != cgl_ctx)
		[self _invalidate];

	if ([self movie] == nil)
		return false;

	// create a visual context, if we don't have one
	if (visualContext == NULL)
	{
		CGSize sz = [self bounds].size;

		dict = [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSDictionary dictionaryWithObjectsAndKeys:
		   [NSNumber numberWithFloat:sz.width],
		   kQTVisualContextTargetDimensions_WidthKey, 
		   [NSNumber numberWithFloat:sz.height],
		   kQTVisualContextTargetDimensions_HeightKey, nil], 
		  kQTVisualContextTargetDimensionsKey, 
		  [NSDictionary dictionaryWithObjectsAndKeys:
		   [NSNumber numberWithFloat:sz.width],
		   kCVPixelBufferWidthKey, 
		   [NSNumber numberWithFloat:sz.height],
		   kCVPixelBufferHeightKey, nil], 
		  kQTVisualContextPixelBufferAttributesKey,
		  nil];

		QTOpenGLTextureContextCreate (NULL, cgl_ctx, pf, (CFDictionaryRef)dict, &visualContext);
		if (visualContext != NULL)
		{
			OSStatus error;
			error = SetMovieVisualContext([[self movie] quickTimeMovie], visualContext);
			SetMoviePlayHints([[self movie] quickTimeMovie],hintsHighQuality, hintsHighQuality);	
			// set Movie to loop
			[[self movie] setAttribute:[NSNumber numberWithBool:YES] forKey:QTMovieLoopsAttribute];					
			[[self movie] gotoBeginning];
			// play the Movie
			[[self movie] setRate:1.0];
		}

		layer_cgl_ctx = cgl_ctx;
	}

	// get the current frame from the movie
	QTVisualContextTask(visualContext);
	if (QTVisualContextIsNewImageAvailable(visualContext, ts))
    {
		if(currentFrame != NULL)
		{
			CVOpenGLTextureRelease(currentFrame);
			currentFrame = NULL;
		}

		QTVisualContextCopyImageForTime(visualContext, NULL, ts, &currentFrame);
    }

	return currentFrame != NULL;
}

//--------------------------------------------------------------------------------------------------

- (void)drawInCGLContext:(CGLContextObj)cgl_ctx
							pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t
							displayTime:(const CVTimeStamp *)ts
{
	if (cgl_ctx != layer_cgl_ctx)
		return;					// we can't draw in a 'foreign' context
	if (currentFrame == NULL)
		return;					// nothing to draw

	// draw the current frame
	[self drawCVOpenGLTexture:currentFrame inCGLContext:cgl_ctx pixelFormat:pf forTime:t];
	// we are done with the frame so we can release it
	CVOpenGLTextureRelease(currentFrame);
	currentFrame = NULL;
	// make sure to call super, as it will flush the context
	[super drawInCGLContext:cgl_ctx pixelFormat:pf forLayerTime:t displayTime:ts];
}

//--------------------------------------------------------------------------------------------------

- (void)drawCVOpenGLTexture:(CVOpenGLTextureRef)tex
								inCGLContext:(CGLContextObj)cgl_ctx
								pixelFormat:(CGLPixelFormatObj)pf forTime:(CFTimeInterval)t
{
	size_t		w, h;
	GLenum		target;
	GLfloat		st[8];
	CGRect		r;

	glClearColor (0, 0, 0, 1);
	glClear (GL_COLOR_BUFFER_BIT);
	if (tex == NULL)
		return;

	r = [self bounds];
	w = r.size.width;
	h = r.size.height;

	glMatrixMode (GL_PROJECTION);
	glLoadIdentity ();
	glOrtho (0, w, 0, h, -1, 1);
	glMatrixMode (GL_MODELVIEW);
	glLoadIdentity ();

	CVOpenGLTextureGetCleanTexCoords (tex, st + 4, st + 2, st + 0, st + 6);

	target = CVOpenGLTextureGetTarget (tex);
	glBindTexture (target, CVOpenGLTextureGetName (tex));
	glEnable (target);

	glBegin (GL_QUADS);
	glVertex2i (0, h);
	glTexCoord2f (st[0], st[1]);
	glVertex2i (w, h);
	glTexCoord2f (st[2], st[3]);
	glVertex2i (w, 0);
	glTexCoord2f (st[4], st[5]);
	glVertex2i (0, 0);
	glTexCoord2f (st[6], st[7]);
	glEnd ();

	glBindTexture (target, 0);
	glDisable (target);
}

//--------------------------------------------------------------------------------------------------

- (void)releaseCGLContext:(CGLContextObj)ctx
{
	[self _invalidate];
	[super releaseCGLContext:ctx];
}

//--------------------------------------------------------------------------------------------------

@end
