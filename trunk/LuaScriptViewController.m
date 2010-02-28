/*
 *  LuaScriptViewController.h
 *  LuaScript
 *
 *  Created by Paolo on 28/02/2010.
 *
 * Copyright (c) 2010 Paolo Manna
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, this list of
 *   conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, this list of
 *   conditions and the following disclaimer in the documentation and/or other materials
 *   provided with the distribution.
 * - Neither the name of the Author nor the names of its contributors may be used to
 *   endorse or promote products derived from this software without specific prior written
 *   permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "LuaScriptViewController.h"
#import "NoodleLineNumberMarker.h"
#import "NoodleLineNumberView.h"

#define CORNER_RADIUS	3.0
#define MARKER_HEIGHT	13.0

@implementation LuaScriptViewController

- (void)dealloc
{
	[programView setHasVerticalRuler: NO];
	[programView setVerticalRulerView: nil];
	[lineNumberView release];
	[errorImage release];
	
	[super dealloc];
}

// Sort of a hack, but we actually don't know when the nib is actually loaded
- (QCPlugIn*) plugIn
{
	QCPlugIn	*rslt	= [super plugIn];
	
	if (programView && !lineNumberView) {
//		NSBundle					*thisBundle	= [NSBundle bundleForClass: [self class]];
//		NSString					*imagePath	= [thisBundle pathForResource: @"error" ofType: @"png"];
		
		lineNumberView = [[NoodleLineNumberView alloc] initWithScrollView: programView];
		[programView setVerticalRulerView:lineNumberView];
		[programView setHasHorizontalRuler:NO];
		[programView setHasVerticalRuler:YES];
		[programView setRulersVisible:YES];
		
//		errorImage	= [[NSImage alloc] initWithContentsOfFile: imagePath];
	}
	
	return rslt;
}

- (void)drawMarkerImageIntoRep:(id)rep
{
	NSBezierPath	*path;
	NSRect			rect;
	
	rect = NSMakeRect(1.0, 2.0, [rep size].width - 2.0, [rep size].height - 3.0);
	
	path = [NSBezierPath bezierPath];
	[path moveToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + NSHeight(rect) / 2)];
	[path lineToPoint:NSMakePoint(NSMaxX(rect) - 5.0, NSMaxY(rect))];
	
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rect) + CORNER_RADIUS, NSMaxY(rect) - CORNER_RADIUS) radius:CORNER_RADIUS startAngle:90 endAngle:180];
	
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(rect) + CORNER_RADIUS, NSMinY(rect) + CORNER_RADIUS) radius:CORNER_RADIUS startAngle:180 endAngle:270];
	[path lineToPoint:NSMakePoint(NSMaxX(rect) - 5.0, NSMinY(rect))];
	[path closePath];
	
	[[NSColor colorWithCalibratedRed:0.90 green:0.15 blue:0.15 alpha:1.0] set];
	[path fill];
	
	[[NSColor colorWithCalibratedRed:0.60 green:0.0 blue:0.0 alpha:1.0] set];
	
	[path setLineWidth:2.0];
	[path stroke];
}

- (NSImage *)markerImageWithSize:(NSSize)size
{
	if (errorImage == nil)
	{
		NSCustomImageRep	*rep;
		
		errorImage = [[NSImage alloc] initWithSize:size];
		rep = [[NSCustomImageRep alloc] initWithDrawSelector:@selector(drawMarkerImageIntoRep:) delegate:self];
		[rep setSize:size];
		[errorImage addRepresentation:rep];
		[rep release];
	}
	return errorImage;
}


- (void)setErrorMarkerAtLine: (NSInteger)aLine
{
	if (errorLineNum  != aLine) {
		if (errorLineNum > 0)
			[lineNumberView removeMarker: [lineNumberView markerAtLine: errorLineNum]];
		
		if (aLine > 0) {
			NoodleLineNumberMarker		*marker;
			
			marker = [[NoodleLineNumberMarker alloc] initWithRulerView: lineNumberView
															lineNumber: aLine
																 image: [self markerImageWithSize:NSMakeSize([lineNumberView ruleThickness], MARKER_HEIGHT)]
														   imageOrigin: NSMakePoint(- (MARKER_HEIGHT / 2), MARKER_HEIGHT / 2)];
			[lineNumberView addMarker:marker];
			[marker release];
		}
		errorLineNum	= aLine;
	}
}

@end
