/*

File: FrequencyLevelsLayer.m

Abstract: Container that creates and handles the frequency levels 

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

#import "FrequencyLevels.h"

#define LEVEL_OFFSET		8
#define LEVEL_WIDTH			30
#define LEVEL_HEIGHT		240

static UInt32 numberOfBandLevels = 8;       // increase this number for more frequency bands
static UInt32 numberOfChannels = 2;         // for StereoMix - If using DeviceMix, you need to get the channel count of the device.

@interface FrequencyLevels	(internal)
	- (void)_levelTimerMethod:(NSTimer*)theTimer;
@end

@implementation FrequencyLevels

//--------------------------------------------------------------------------------------------------

+ (FrequencyLevels*)levelsWithMovie:(QTMovie *)movie
{
	FrequencyLevels				*levels;
	
	levels = [[FrequencyLevels alloc] init];
	[levels setMovie:movie];
	return [levels autorelease];
}

//--------------------------------------------------------------------------------------------------

- (id)init
{
	CGImageRef		peterImage = nil;

	self = [super init];
	
	// allocate memory for the QTAudioFrequencyLevels struct and set it up
    // depending on the number of channels and frequency bands you want    
    freqResults = malloc(offsetof(QTAudioFrequencyLevels, level[numberOfBandLevels * numberOfChannels]));

    freqResults->numChannels = numberOfChannels;
    freqResults->numFrequencyBands = numberOfBandLevels;
    
    // create an array and load up the UI elements, each NSLevelIndicator has
    // the appropriate tag added in IB
    frequencyLayers = [NSMutableArray array];
    [frequencyLayers retain];

	// load image of Peter for the level indicator layers
	NSURL	*imageURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Peter" ofType:@"png"]];
	
	CGImageSourceRef	source     = CGImageSourceCreateWithURL((CFURLRef)imageURL, nil);
	peterImage = CGImageSourceCreateImageAtIndex(source, 0, nil);
	CFRelease (source);

	// create the layers
	container = [[LKLayer layer] retain];
	[container setBounds:CGRectMake (0, 0, ((numberOfBandLevels * numberOfChannels) * (LEVEL_WIDTH + LEVEL_OFFSET)) + LEVEL_OFFSET, LEVEL_HEIGHT)];

	int			i, j;
	CGFloat		x = LEVEL_OFFSET + (LEVEL_WIDTH * 0.5);		// setup the center of the first layer
	
	for(j = 0; j < numberOfChannels; j++)
	{
		for(i = 0; i < numberOfBandLevels; i++)
		{
			LKLayer		*levelLayer = [LKLayer layer];
			[levelLayer setBounds:CGRectMake (0, 0, LEVEL_WIDTH, LEVEL_HEIGHT)];
			levelLayer.shadowOpacity = 0.75;				// add some shadow
			[frequencyLayers addObject:levelLayer];
			[container addSublayer:levelLayer];
			levelLayer.position = CGPointMake(x, 0);		// position the layer
			levelLayer.contents = (id)peterImage;			// set Peter's image as the default content
			if(j > 0)										// flip the right channel horizontally so the images are facing each other
				levelLayer.transform = LKTransformMakeScale(-1.0, 1.0, 1.0);

			x += LEVEL_OFFSET + LEVEL_WIDTH;
		}
	}
	return self;
}

//--------------------------------------------------------------------------------------------------

- (void)dealloc
{
	[container release];
	[frequencyLayers release];
	free(freqResults);
	[super dealloc];
}

//--------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------

- (void)_invalidate
{
	if ([[movie attributeForKey:QTMovieHasAudioAttribute] boolValue]) 
	{
		// do this once per movie to establish metering
		(void)SetMovieAudioFrequencyMeteringNumBands([movie quickTimeMovie], kQTAudioMeter_StereoMix, &numberOfBandLevels);
	}
}

//--------------------------------------------------------------------------------------------------

- (void)setMovie:(QTMovie *)inMovie
{
	movie = inMovie;
	if (movie)
	{
		[self _invalidate];
		[container setNeedsDisplay];
	}

}

//--------------------------------------------------------------------------------------------------

- (LKLayer*)layer
{
	return container;
}

//--------------------------------------------------------------------------------------------------

// called when the button is pressed - turns the level meters on/off by setting up a timer
- (void)toggleFreqLevels:(NSCellStateValue)state
{
    if (NSOnState == state) {
    	// turning it on, set up a timer and add it to the run loop
        timer = [NSTimer timerWithTimeInterval:1.0/15 target:self selector:@selector(_levelTimerMethod:) userInfo:nil repeats:YES];
        
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:(NSString *)kCFRunLoopCommonModes];
		container.hidden = NO;
    } else {
		// turning it off, stop the timer and hide the level layers
		[timer invalidate];
		container.hidden = YES;
	}
}


//--------------------------------------------------------------------------------------------------

- (void)_levelTimerMethod:(NSTimer*)theTimer
{
	UInt8 i, j;
	NSEnumerator *enumerator = [frequencyLayers objectEnumerator]; // get a enumerator for the array of NSLevelIndicator objects
    
    // get the levels from the movie
	OSStatus err = GetMovieAudioFrequencyLevels([movie quickTimeMovie], kQTAudioMeter_StereoMix, freqResults);
    if (!err) 
    {
		// iterate though the frequency level array and though the UI elements getting
		// and setting the levels appropriately
		for (i = 0; i < freqResults->numChannels; i++) {
			for (j = 0; j < freqResults->numFrequencyBands; j++) {
				// the frequency levels are Float32 values between 0. and 1.
				Float32 value = (freqResults->level[(i * freqResults->numFrequencyBands) + j]) * LEVEL_HEIGHT;
				LKLayer		*layer = [enumerator nextObject];
				layer.bounds = CGRectMake(0, 0, LEVEL_WIDTH, value);
			}
		}
	}
}

@end
