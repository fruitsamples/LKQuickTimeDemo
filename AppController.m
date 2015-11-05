/*

File: AppController.m

Abstract: Main app controller

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

#import "AppController.h"

@interface AppController (private)

- (void)_loadMovie:(NSString *)path;

@end

@implementation AppController

//--------------------------------------------------------------------------------------------------

- (void)awakeFromNib
{
	[[contentWindow contentView] setWantsLayer:YES];							// setup the content view to use layers
	
	LKLayer *root = [[contentWindow contentView] layer];						// create a layer to contain all of our layers
	
	root.layoutManager = [LKConstraintLayoutManager layoutManager];				// use constraint layout to allow sublayers to center themselves

	container = [LKLayer layer];
	container.bounds = root.bounds;
	container.frame = root.frame;
	container.position = CGPointMake(root.bounds.size.width * 0.5, root.bounds.size.height * 0.5);
	[root insertSublayer:container atIndex:0];	// insert layer on the bottom of the stack so it is behind the controls
	root.autoresizingMask = kLKLayerWidthSizable | kLKLayerHeightSizable;	// make it resize when its superlayer does
	container.autoresizingMask = kLKLayerWidthSizable | kLKLayerHeightSizable;	// make it resize when its superlayer does

}

//--------------------------------------------------------------------------------------------------

- (void)applicationWillFinishLaunching:(NSNotification *)note
{
    NSString *moviePath;

    /* See if we have a known pathname */
    moviePath = [[NSUserDefaults standardUserDefaults] stringForKey:@"MoviePath"];
    if(moviePath)
    {
        [self _loadMovie:moviePath];
    } else {
		[self performSelector:@selector(openMovie:) withObject:self afterDelay:0];
	}
}

//--------------------------------------------------------------------------------------------------

- (void)openMovie:(id)sender
{
    NSOpenPanel *openPanel;
    int rv;
    
    openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setResolvesAliases:YES];
    [openPanel setCanChooseFiles:YES];
    [openPanel setTitle:@"Select a movie with audio"];
    
    rv = [openPanel runModalForTypes:nil];
    if(rv == NSFileHandlingPanelOKButton)
        [self _loadMovie:[openPanel filename]];
}

//--------------------------------------------------------------------------------------------------

- (void)_loadMovie:(NSString *)path
{
    NSError	*error;
        
	[qtMovie release];
    qtMovie = [[QTMovie movieWithFile:path error:&error] retain];
    if(qtMovie)
    {
 		if(movieLayer)	// if we already have a movie layer, just set the movie on it
		{
			movieLayer.movie = qtMovie;
		} else {
			movieLayer = [MovieLayer layerWithMovie:qtMovie];	// create our movie layer
			movieLayer.frame = container.frame;					// size the layer
			movieLayer.autoresizingMask = kLKLayerWidthSizable | kLKLayerHeightSizable;	// scale the movie layer with the container (it will resize with the window)
			[container insertSublayer:movieLayer atIndex:0];	// insert layer on the bottom of the stack
			movieLayer.position = container.position;			// center it on the container
		}
		movieLayer.beginTime = LKCurrentTime ();		// set the start time for the layer

 		if(levels)	// if we already have a frequence level container, just set the movie on it
		{
			[levels setMovie:qtMovie];
		} else {
			levels = [[FrequencyLevels levelsWithMovie:qtMovie] retain];
			[levels layer].autoresizingMask = kLKLayerMinXMargin | kLKLayerMaxXMargin | kLKLayerMinYMargin | kLKLayerMaxYMargin;	// keep the levels layer at the same size
			[container addSublayer:[levels layer]];
			[levels layer].position = container.position;
			[levels toggleFreqLevels:[frequencyLevels state]];
		}
		/* save movie path as default for next time */
		[[NSUserDefaults standardUserDefaults] setObject:path forKey:@"MoviePath"];
        [[NSUserDefaults standardUserDefaults] synchronize];
		[contentWindow setTitleWithRepresentedFilename:path];
	}
}

//--------------------------------------------------------------------------------------------------

- (IBAction)setOpacity:(id)sender
{
	movieLayer.opacity = [sender floatValue];		// set the opacity of the movie layer
}

//--------------------------------------------------------------------------------------------------

- (IBAction)toggleBackgroundFilter:(id)sender
{
    if ([sender state] == NSOnState)
    {
        CIFilter    *effect;
        
		effect = [CIFilter filterWithName:@"CIKaleidoscope"];		// create effect filter
        [effect setDefaults];										// make sure all paramters are set to something reasonable
        [effect setValue:[CIVector vectorWithX:movieLayer.bounds.size.width * 0.5 Y:movieLayer.bounds.size.height * 0.5] forKey:kCIInputCenterKey];	// set the center of the effect to be the center of the layer        
        [movieLayer setFilters:[NSArray arrayWithObject:effect]];	// set the effect on the layer
    } else {
        [movieLayer setFilters:nil];								// remove the effect
    }

}

//--------------------------------------------------------------------------------------------------

- (IBAction)toggleForegroundFilter:(id)sender
{
    if ([sender state] == NSOnState)
    {
        CIFilter    *effect;
        
		effect = [CIFilter filterWithName:@"CIBloom"];				// create effect filter
        [effect setDefaults];										// make sure all paramters are set to something reasonable      
        [container setFilters:[NSArray arrayWithObject:effect]];	// set the effect on the layer
    } else {
        [container setFilters:nil];									// remove the effect
    }
}

//--------------------------------------------------------------------------------------------------

- (IBAction)toggleFrequenceyLevels:(id)sender
{
	[levels toggleFreqLevels:[sender state]];
}

//--------------------------------------------------------------------------------------------------
#pragma mark Application delegate
//--------------------------------------------------------------------------------------------------

// quit when window is closed
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}


@end
