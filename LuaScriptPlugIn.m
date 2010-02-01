/*
 *  LuaScriptPlugIn.m
 *  LuaScript
 *
 *  Created by Paolo on 05/05/2009.
 *
 * Copyright (c) 2009 Paolo Manna
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

#import <OpenGL/CGLMacro.h>

#import "LuaScriptPlugIn.h"

#define	kQCPlugIn_Name				@"Lua"
#define	kQCPlugIn_Description		"This patch executes a Lua script with an arbitrary number of input / output parameters.\n"\
									"The \"main\" function of the patch is executed, taking as input the contents of the \"inputs\" "\
									"table and returning values inside the \"outputs\" table.\n"\
									"Only some classes for values are supported for use as variables in Lua code: Boolean, Number, String, Structures. "\
									"Other types will get translated to Lua user data.\n"\
									"Structures are translated to tables in Lua and can contain in input different types of data, that will, again, "\
									"become userdata in Lua if not recognized. In output, tables are always translated to dictionary structures.\n"\
									"Experimental support exists for type Image, that is passed around Lua as user data.\n"\
									"The script always gets executed first for error check with all input ports valued to defaults set in the code "\
									"(input types are inferred by the default values themselves)."

// This could be nice, but actually not needed, as we can always create an input and connect it to Patch Time
//#define	TIME_BASED

// WARNING: Not supported at all, private interfaces!
@interface QCImage: NSObject
- (id)initWithFile:(id)aFile options: (id)someOpts;
@end

static NSArray		*keyWords;
static NSArray		*libWords;
static NSArray		*varWords;
static QCImage		*dummyImage;
static NSColor		*dummyColor;
static NSArray		*dummyStructure;

@implementation LuaScriptPlugIn

@synthesize syntaxError;

// Utility function, from PiL 24.2.3, expanded and adapted to Cocoa
static void tableDump(lua_State *L, int idx, NSMutableString *outStr)
{
	lua_pushnil(L);
	while (lua_next(L, idx))
	{
		if (lua_type(L, -2) == LUA_TSTRING) {
			[outStr appendFormat: @"[\"%s\"]=", lua_tostring(L, -2)];
		} else if (lua_type(L, -2) == LUA_TNUMBER) {
			[outStr appendFormat: @"[%d]=", lua_tointeger(L, -2)];
		} else {
			// Unrecognised key type
		}
		// Create the output according to the type we've found
		switch (lua_type(L, -1)) {
			case LUA_TBOOLEAN:
				[outStr appendString: (lua_toboolean(L, -1) ? @"true, " : @"false, ")];
				break;
			case LUA_TNUMBER:
				[outStr appendFormat: @"%g, ", lua_tonumber(L, -1)];
				break;
			case LUA_TSTRING:
				[outStr appendFormat: @"\"%s\", ", lua_tostring(L, -1)];
				break;
			case LUA_TLIGHTUSERDATA:
			case LUA_TUSERDATA:
				[outStr appendFormat: @"<%s>, ", lua_typename(L, -1)];
				break;
			case LUA_TTABLE:
				[outStr appendString: @"{"];
				tableDump(L, -2, outStr);
				[outStr appendString: @"}, "];
				break;
		}
		lua_pop(L, 1);
	}
}

static void stackDump (lua_State *L)
{
	int				ii;
	int				top	= lua_gettop(L);
	NSMutableString	*outStr	= [NSMutableString string];
	
	for (ii = 1; ii <= top; ii++) {  /* repeat for each level */
        int		t	= lua_type(L, ii);
		
        switch (t) {
			case LUA_TSTRING:  /* strings */
				[outStr appendFormat: @"\"%s\" | ", lua_tostring(L, ii)];
				break;
				
			case LUA_TBOOLEAN:  /* booleans */
				[outStr appendString: (lua_toboolean(L, ii) ? @"true | " : @"false | ")];
				break;
				
			case LUA_TNUMBER:  /* numbers */
				[outStr appendFormat: @"%g | ", lua_tonumber(L, ii)];
				break;
				
			case LUA_TTABLE:  /* tables */
				[outStr appendString: @"{"];
				tableDump(L, ii, outStr);
				[outStr appendString: @"} | "];
				break;
				
			default:  /* other values */
				[outStr appendFormat: @"<%s> | ", lua_typename(L, t)];
				break;
				
        }
	}
	NSLog(@"Lua Stack -> %@", outStr);
}

// Image isn't supported easily, we should implement both input- and output-image protocols
static int imageUserDataType(lua_State *L)
{
	lua_pushlightuserdata(L, dummyImage);
	
	return 1;
}

static int colorUserDataType(lua_State *L)
{
	lua_pushlightuserdata(L, dummyColor);
	
	return 1;
}

static int structureUserDataType(lua_State *L)
{
	lua_pushlightuserdata(L, dummyStructure);
	
	return 1;
}

+ (NSDictionary*) attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys: kQCPlugIn_Name, QCPlugInAttributeNameKey,
													[NSString stringWithUTF8String: kQCPlugIn_Description], QCPlugInAttributeDescriptionKey,
													nil];
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
	// No fixed attributes
	return nil;
}

+ (QCPlugInExecutionMode) executionMode
{
	return kQCPlugInExecutionModeProcessor;
}

+ (QCPlugInTimeMode) timeMode
{
#ifdef TIME_BASED
	return kQCPlugInTimeModeTimeBase;
#else
	return kQCPlugInTimeModeNone;
#endif
}

- (id) init
{
	if(self = [super init]) {
		NSString	*defPath	= [[NSBundle bundleForClass: [self class]] pathForResource: @"logo" ofType: @"gif"];
		
		if (!keyWords)
			keyWords		= [[NSArray arrayWithObjects: @"and", @"break", @"do", @"else", @"elseif", @"end", @"false",
														@"for", @"function", @"if", @"in", @"local", @"nil", @"not",
														@"or", @"repeat", @"return", @"then", @"true", @"until", @"while", nil] retain];
		if (!libWords)
			libWords		= [[NSArray arrayWithObjects: @"coroutine", @"package", @"string", @"table", @"math", @"io", @"os", @"debug", nil] retain];
		if (!varWords)
			varWords		= [[NSArray arrayWithObjects: @"inputs", @"outputs", @"patchTime", @"main",
														@"imageType", @"colorType", @"structureType", nil] retain];
		
		// Dummy vars used to force a userdata type
		if (!dummyColor)
			dummyColor		= [[NSColor blackColor] retain];
		if (!dummyStructure)
			dummyStructure	= [[NSArray	alloc] init];
		if (!dummyImage)
			dummyImage		= [[QCImage alloc] initWithFile: defPath options: nil];
		
		_inputKeys		= [[NSMutableDictionary alloc] initWithCapacity: 1];
		_outputKeys		= [[NSMutableDictionary alloc] initWithCapacity: 1];
		
		syntaxError		= [[NSString alloc] init];
	}
	
	return self;
}

- (void) dealloc
{
	[_outputKeys release];
	[_inputKeys release];
	[syntaxError release];
	
	[programString release];
	
	[super dealloc];
}

+ (NSArray*) plugInKeys
{
	/*
	Return a list of the KVC keys corresponding to the internal settings of the plug-in.
	*/
	return [NSArray arrayWithObject: @"programString"];
}

- (void)_interpretProgram
{
	const char	*progCString	= NULL;
	
	if (!L) {
		L	= lua_open();
		
		lua_gc(L, LUA_GCSTOP, 0);  /* stop collector during initialization */
		luaL_openlibs(L);  /* open libraries */
		lua_register(L, "imageType", imageUserDataType);
		lua_register(L, "colorType", colorUserDataType);
		lua_register(L, "structureType", structureUserDataType);
		lua_gc(L, LUA_GCRESTART, 0);
	}
	
	_readyToRun	= NO;
	
	lua_settop(L, 0);	// Clean stack
	
	if (!(progCString = [[programString string] UTF8String]))
		return;
	
	if (!luaL_dostring(L, progCString)) {
		NSEnumerator	*enumKeys;
		NSObject		*keyName;
		
		if (_checkSyntax) {
			[self setSyntaxError: @"LuaScript Program OK"];
		}
		
		// Create new inputs from Lua table
		lua_getglobal(L, "inputs");
		if (lua_gettop(L)) {
			if (lua_type(L, -1) == LUA_TTABLE) {
				NSArray			*orderedInputs	= [[_inputKeys allKeys] sortedArrayUsingSelector: @selector(compare:)];
				NSMutableArray	*oldKeys		= [NSMutableArray arrayWithArray: orderedInputs];
				
				lua_pushnil(L);
				while (lua_next(L, 1))
				{
					id			key			= nil;
					
					if (lua_type(L, -2) == LUA_TSTRING) {
						key		= [NSString stringWithUTF8String: lua_tostring(L, -2)];
					} else if (lua_type(L, -2) == LUA_TNUMBER) {
						key		= [NSNumber numberWithInt: lua_tointeger(L, -2)];
					} else {
						// Unrecognised key type
					}
					
					if (key) {
						NSString		*inputType	= nil;
						NSDictionary	*portAttrs	= nil;
						
						// Create the input according to the type we've found
						switch (lua_type(L, -1)) {
							case LUA_TBOOLEAN:
								inputType	= QCPortTypeBoolean;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: (BOOL)lua_toboolean(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   inputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TNUMBER:
								inputType	= QCPortTypeNumber;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithDouble: lua_tonumber(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   inputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TSTRING:
								inputType	= QCPortTypeString;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithUTF8String: lua_tostring(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   inputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TTABLE:
								inputType	= QCPortTypeStructure;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: inputType, QCPortAttributeTypeKey,
																						[key description], QCPortAttributeNameKey, nil];
								break;
							case LUA_TLIGHTUSERDATA:
								{
									id	value	= lua_touserdata(L, -1);
									
									if ([value isKindOfClass: [QCImage class]]) {
										inputType	= QCPortTypeImage;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: inputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey,
																								nil];
									} else if ([value isKindOfClass: [NSColor class]]) {
										inputType	= QCPortTypeColor;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: value, QCPortAttributeDefaultValueKey,
																								inputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey,
																								nil];
									} else {
										inputType	= QCPortTypeStructure;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: inputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey, nil];
									}
								}
								break;
						}
						
						if (inputType && portAttrs) {
							if ([oldKeys containsObject: key]) {
								NSDictionary	*oldAttrs	= [_inputKeys objectForKey: key];
								
								// Refresh inputs only if there wasn't one with the same type
								if (![inputType isEqualToString: [oldAttrs objectForKey: QCPortAttributeTypeKey]]) {
									[self removeInputPortForKey: [key description]];
									[self addInputPortWithType: inputType
														forKey: [key description]
												withAttributes: portAttrs];
								}
								
								[oldKeys removeObject: key];
							} else {
								// Completely new input, add it
								[self addInputPortWithType: inputType
													forKey: [key description]
											withAttributes: portAttrs];
							}
							// Add or replace the key to our dictionary
							[_inputKeys setObject: portAttrs forKey: key];
						}
					}
					lua_pop(L, 1);
				}
				
				// Remove unused old inputs
				enumKeys	= [oldKeys objectEnumerator];
				while ((keyName = [enumKeys nextObject]) != nil) {
					[self removeInputPortForKey: [keyName description]];
					[_inputKeys removeObjectForKey: keyName];
				}
			}
			lua_pop(L, 1);
		}
		
		// Create new outputs from Lua table
		lua_getglobal(L, "outputs");
		if (lua_gettop(L)) {
			if (lua_type(L, -1) == LUA_TTABLE) {
				NSArray			*orderedOutputs	= [[_outputKeys allKeys] sortedArrayUsingSelector: @selector(compare:)];
				NSMutableArray	*oldKeys		= [NSMutableArray arrayWithArray: orderedOutputs];
				
				lua_pushnil(L);
				while (lua_next(L, 1))
				{
					id			key			= nil;
					
					if (lua_type(L, -2) == LUA_TSTRING) {
						key		= [NSString stringWithUTF8String: lua_tostring(L, -2)];
					} else if (lua_type(L, -2) == LUA_TNUMBER) {
						key		= [NSNumber numberWithInt: lua_tointeger(L, -2)];
					} else {
						// Unrecognised key type
					}
					
					if (key) {
						NSString		*outputType	= nil;
						NSDictionary	*portAttrs	= nil;
						
						// Create the input according to the type we've found
						switch (lua_type(L, -1)) {
							case LUA_TBOOLEAN:
								outputType	= QCPortTypeBoolean;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: (BOOL)lua_toboolean(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   outputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TNUMBER:
								outputType	= QCPortTypeNumber;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithDouble: lua_tonumber(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   outputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TSTRING:
								outputType	= QCPortTypeString;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithUTF8String: lua_tostring(L, -1)],
																					   QCPortAttributeDefaultValueKey,
																					   outputType, QCPortAttributeTypeKey,
																					   [key description], QCPortAttributeNameKey,
																					   nil];
								break;
							case LUA_TTABLE:
								outputType	= QCPortTypeStructure;
								portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: outputType, QCPortAttributeTypeKey,
																						[key description], QCPortAttributeNameKey, nil];
								break;
							case LUA_TLIGHTUSERDATA:
								{
									id	value	= lua_touserdata(L, -1);
									
									if ([value isKindOfClass: [QCImage class]]) {
										outputType	= QCPortTypeImage;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: value, QCPortAttributeDefaultValueKey,
																								outputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey,
																								nil];
									} else if ([value isKindOfClass: [NSColor class]]) {
										outputType	= QCPortTypeColor;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: value, QCPortAttributeDefaultValueKey,
																								outputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey,
																								nil];
									} else {
										outputType	= QCPortTypeStructure;
										portAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: outputType, QCPortAttributeTypeKey,
																								[key description], QCPortAttributeNameKey, nil];
									}
								}
								break;
						}
						
						if (outputType && portAttrs) {
							if ([oldKeys containsObject: key]) {
								NSDictionary	*oldAttrs	= [_outputKeys objectForKey: key];
								
								// Refresh inputs only if there wasn't one with the same type
								if (![outputType isEqualToString: [oldAttrs objectForKey: QCPortAttributeTypeKey]]) {
									[self removeOutputPortForKey: [key description]];
									[self addOutputPortWithType: outputType
														 forKey: [key description]
												 withAttributes: portAttrs];
								}
								
								[oldKeys removeObject: key];
							} else {
								// Completely new input, add it
								[self addOutputPortWithType: outputType
													 forKey: [key description]
											 withAttributes: portAttrs];
							}
							// Add the key to our dictionary
							[_outputKeys setObject: portAttrs forKey: key];
						}
					}
					lua_pop(L, 1);
				}
				
				// Remove unused old outputs
				enumKeys	= [oldKeys objectEnumerator];
				while ((keyName = [enumKeys nextObject]) != nil) {
					[self removeOutputPortForKey: [keyName description]];
					[_outputKeys removeObjectForKey: keyName];
				}
			}
			lua_pop(L, 1);
		}
		_readyToRun		= YES;
		_programChanged	= YES;
	} else {
		if (_checkSyntax) {
			[self setSyntaxError: [NSString stringWithFormat: @"LuaScript Program Error: %s", lua_tostring(L, -1)]]; 
		}
		lua_pop(L, 1);
	}
}

- (NSMutableAttributedString *)_coloredStringWithString: (NSString *)aProgram
{
	NSDictionary				*defAttrs	= [NSDictionary dictionaryWithObjectsAndKeys: [NSFont fontWithName: @"Monaco" size: 10], NSFontAttributeName, nil];
	NSMutableAttributedString	*result		= [[NSMutableAttributedString alloc] initWithString: aProgram attributes:defAttrs];
	NSCharacterSet				*whiteChars	= [NSCharacterSet characterSetWithCharactersInString: @" \r\n\t;:,.()-+="];
	NSCharacterSet				*strDelim	= [NSCharacterSet characterSetWithCharactersInString: @"\""];
	NSString					*wholeWord;
	NSScanner					*strScan;
    NSColor						*blue		= [NSColor blueColor];
    NSColor						*red		= [NSColor redColor];
    NSColor						*purple		= [NSColor purpleColor];
    NSColor						*magenta	= [NSColor magentaColor];
    NSColor						*gray		= [NSColor grayColor];
    NSUInteger					length		= [result length];
    NSRange						area		= {0, length};
    NSRange						found;
	
	[result beginEditing];
	
	strScan	= [NSScanner scannerWithString: aProgram];
	[strScan setCharactersToBeSkipped: whiteChars];
	
	// Scan and identify key words, wherever they are
	while (![strScan isAtEnd]) {
		if ([strScan scanUpToCharactersFromSet: whiteChars intoString: &wholeWord]) {
			found.length	= [wholeWord length];
			found.location	= [strScan scanLocation] - found.length;
			
			if ([keyWords containsObject: wholeWord])
				[result addAttribute: NSForegroundColorAttributeName
							   value: blue
							   range: found];
			
			if ([libWords containsObject: wholeWord])
				[result addAttribute: NSForegroundColorAttributeName
							   value: red
							   range: found];
			
			if ([varWords containsObject: wholeWord])
				[result addAttribute: NSForegroundColorAttributeName
							   value: purple
							   range: found];
		}
	}
	
	// Detects double-quoted strings
	while (area.length > 0) {
		NSRange	end;
		
		found	= [aProgram rangeOfCharacterFromSet: strDelim
											options: 0
											  range: area];
		if (found.location == NSNotFound)
			break;
		area.location	= NSMaxRange(found);
		area.length		= length - area.location;
		
		end		= [aProgram rangeOfCharacterFromSet: strDelim
											options: 0
											  range: area];
		if (end.location == NSNotFound)
			break;
		area.location	= NSMaxRange(end);
		area.length		= length - area.location;
		
		found.length	= end.location - found.location + 1;
		
		[result removeAttribute: NSForegroundColorAttributeName range: found];
		[result addAttribute: NSForegroundColorAttributeName
					   value: magenta
					   range: found];
	}
	
	[strScan setScanLocation: 0];
	[strScan setCharactersToBeSkipped: [NSCharacterSet whitespaceCharacterSet]];
	
	while (![strScan isAtEnd]) {
		[strScan scanUpToString: @"--" intoString: nil];
		found.location	= [strScan scanLocation];
		[strScan scanString: @"--" intoString: nil];
		if ([strScan isAtEnd])
			break;
		[strScan scanUpToCharactersFromSet: [NSCharacterSet newlineCharacterSet] intoString: nil];
		found.length	= [strScan scanLocation] - found.location;
		
		[strScan setScanLocation: [strScan scanLocation] - 1];
		[result removeAttribute: NSForegroundColorAttributeName range: found];
		[result addAttribute: NSForegroundColorAttributeName
					   value: gray
					   range: found];
	}
	
	// Reset the default color
	found.location	= length;
	found.length	= 0;
	[result removeAttribute: NSForegroundColorAttributeName range: found];
	[result addAttribute: NSForegroundColorAttributeName
				   value: [NSColor blackColor]
				   range: found];
	
	[result endEditing];
	
	return [result autorelease];
}

- (void)setProgramString: (NSAttributedString *)aProgram
{
	NSString	*contentStr	= [aProgram string];
	BOOL		sameContent	= [[programString string] isEqualToString: contentStr];
	
	if (programString != aProgram) {
		[programString release];
		programString = [aProgram retain];
		
		if (!sameContent || _checkSyntax)
			[self _interpretProgram];
	}
}

- (NSAttributedString *)programString
{
	// Get a default code sample if we're starting new
	if (!programString) {
		NSString			*defPath	= [[NSBundle bundleForClass: [self class]] pathForResource: @"Default" ofType: @"lua"];
		
		[self setProgramString: [self _coloredStringWithString: [NSString stringWithContentsOfFile: defPath encoding: NSUTF8StringEncoding error: nil]]];
	}
	
	return programString;
}


- (QCPlugInViewController*) createViewController
{
	return [[QCPlugInViewController alloc] initWithPlugIn: self viewNibName: @"Settings"];
}

// Bound as a target to a button in the IB file
- (IBAction)checkSyntax: (id)sender
{
	_checkSyntax	= YES;
	[self setProgramString: [self _coloredStringWithString: [programString string]]];
	_checkSyntax	= NO;
}

@end

@implementation LuaScriptPlugIn (Execution)

- (BOOL) startExecution:(id<QCPlugInContext>)context
{
	return YES;
}

- (void) enableExecution:(id<QCPlugInContext>)context
{
}

- (void)_unpackTableInContext: (id<QCPlugInContext>)context
					  atIndex: (NSInteger)anIdx
					 onTarget: (id)aTarget
					 selector: (SEL)aSelector
{
	lua_pushnil(L);
	while (lua_next(L, anIdx))
	{
		id			key			= nil;
		
		if (lua_type(L, -2) == LUA_TSTRING) {
			key		= [NSString stringWithUTF8String: lua_tostring(L, -2)];
		} else if (lua_type(L, -2) == LUA_TNUMBER) {
			key		= [NSNumber numberWithInt: lua_tointeger(L, -2)];
		} else {
			// Unrecognised key type
		}
		
		if (key) {
			id		outputValue	= nil;
			
			// Create the output according to the type we've found
			switch (lua_type(L, -1)) {
				case LUA_TBOOLEAN:
					outputValue	= [NSNumber numberWithBool: (BOOL)lua_toboolean(L, -1)];
					break;
				case LUA_TNUMBER:
					outputValue	= [NSNumber numberWithDouble: lua_tonumber(L, -1)];
					break;
				case LUA_TSTRING:
					outputValue	= [NSString stringWithUTF8String: lua_tostring(L, -1)];
					break;
				case LUA_TLIGHTUSERDATA:
				case LUA_TUSERDATA:
					outputValue	= lua_touserdata(L, -1);
					// WARNING: This is NOT documented anywhere, but comes just as convenient
					// to avoid rendering an image (as we should do if using input-output image sources)
					if ([outputValue isKindOfClass: NSClassFromString(@"QCPlugInInputImage")]) {
						outputValue	= [outputValue image];
					}
					break;
				case LUA_TTABLE:
					outputValue	= [NSMutableDictionary dictionaryWithCapacity: 2];
					[self _unpackTableInContext: context
										atIndex: -2
									   onTarget: outputValue
									   selector: @selector(setObject:forKey:)];
					break;
			}
			@try {
				[aTarget performSelector: aSelector
							  withObject: outputValue
							  withObject: [key description]];
			}
			@catch (NSException * exc) {
				NSLog(@"%s: %@", __PRETTY_FUNCTION__, [exc reason]);
			}
		}
		lua_pop(L, 1);
	}
}

- (void) _assignToLuaTable: (id) value
{
	if ([value isKindOfClass: [NSArray class]]) {
		// Array, crawl through indexes, and push related values
		NSInteger	ii, numElements	= [(NSArray *)value count];
		
		for (ii = 0; ii < numElements; ii++) {
			id		obj			= [(NSArray *)value objectAtIndex: ii];
			
			if ([obj isKindOfClass: [NSNumber class]]) {
				// Pure number, no boolean
				lua_pushnumber(L, [obj doubleValue]);
			} else if ([obj isKindOfClass: [NSString class]]) {
				// String
				lua_pushstring(L, [obj UTF8String]);
			} else if ([obj isKindOfClass: [NSArray class]] || [obj isKindOfClass: [NSDictionary class]]) {
				// Table, create a new one
				lua_createtable(L, [obj count], 0);
				[self _assignToLuaTable: obj];
			} else {
				// Anything else, lightuserdata
				lua_pushlightuserdata(L, obj);
			}
			lua_setfield(L, -2, [[NSString stringWithFormat: @"%d", ii + 1] UTF8String]);
		}
	} else if ([value isKindOfClass: [NSDictionary class]]) {
		// Dictionary, browse keys and assign values to table
		NSEnumerator	*enumKeys	= [(NSDictionary *)value keyEnumerator];
		id				dictKey;
		
		while ((dictKey = [enumKeys nextObject]) != nil) {
			id		obj	= [(NSDictionary *)value objectForKey: dictKey];
			
			if ([obj isKindOfClass: [NSNumber class]]) {
				lua_pushnumber(L, [obj doubleValue]);
			} else if ([obj isKindOfClass: [NSString class]]) {
				lua_pushstring(L, [obj UTF8String]);
			} else if ([obj isKindOfClass: [NSArray class]] || [obj isKindOfClass: [NSDictionary class]]) {
				// See if a table with that name is already in, create one otherwise
				lua_getfield(L,  -1, [dictKey UTF8String]);
				
				if (lua_type(L, -1) == LUA_TNIL) {
					lua_pop(L, 1);
					lua_createtable(L, [obj count], 0);
				}
				[self _assignToLuaTable: obj];
			} else {
				lua_pushlightuserdata(L, obj);
			}
			lua_setfield(L, -2, [dictKey UTF8String]);
		}
	}
	
}

- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary*)arguments
{
	if (!L)
		[self _interpretProgram];
	
	if (!_readyToRun)
		return YES;
	
	lua_settop(L, 0);	// Clean stack
	
	// Assign input values
	lua_getglobal(L, "inputs");
	if (lua_gettop(L)) {
		if (lua_type(L, -1) == LUA_TTABLE) {
			NSEnumerator	*enumInputs	= [_inputKeys keyEnumerator];
			id				key;
			
			while ((key = [enumInputs nextObject]) != nil) {
				NSString		*keyName	= [key description];
				NSDictionary	*inputDict	= [_inputKeys objectForKey: key];
				
				if ([self didValueForInputKeyChange: keyName] || _programChanged) {
					id			value	= [self valueForInputKey: keyName];
					NSString	*type	= [inputDict objectForKey: QCPortAttributeTypeKey];
					
					// For the moment, we ignore images
					if ([type isEqualToString: QCPortTypeBoolean]) {
						lua_pushboolean(L, [value boolValue]);
						lua_setfield(L, -2, [keyName UTF8String]);
					} else if ([type isEqualToString: QCPortTypeNumber]) {
						lua_pushnumber(L, [value doubleValue]);
						lua_setfield(L, -2, [keyName UTF8String]);
					} else if ([type isEqualToString: QCPortTypeString]) {
						lua_pushstring(L, [value UTF8String]);
						lua_setfield(L, -2, [keyName UTF8String]);
					} else if ([type isEqualToString: QCPortTypeColor]) {
						lua_pushlightuserdata(L, value);
						lua_setfield(L, -2, [keyName UTF8String]);
					} else if ([type isEqualToString: QCPortTypeImage]) {
						lua_pushlightuserdata(L, value);
						lua_setfield(L, -2, [keyName UTF8String]);
					} else if ([type isEqualToString: QCPortTypeStructure]) {
						// Push on the stack the table name
						lua_getfield(L,  -1, [keyName UTF8String]);
						
						[self _assignToLuaTable: value];
						
						// Pop the table
						lua_pop(L, 1);
					}
				}
			}
		}
		lua_pop(L, 1);
	}
	
	
#ifdef TIME_BASED
	// Updates time (if it doesn'exist, it's created)
	lua_pushnumber(L, time);
	lua_setglobal(L, "patchTime");
#endif
	
	// Call the main function
	lua_getglobal(L, "main");
	if (!lua_pcall(L, 0, 0, 0)) {
		
		// Updates output values
		lua_getglobal(L, "outputs");
		if (lua_gettop(L)) {
			if (lua_type(L, -1) == LUA_TTABLE) {
				[self _unpackTableInContext: context
									atIndex: 1
								   onTarget: self 
								   selector: @selector(setValue:forOutputKey:)];
			}
			lua_pop(L, 1);
		}
		
		_programChanged	= NO;
	} else {
		NSLog(@"LuaScript main(): %s", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	
	return YES;
}

- (void) disableExecution:(id<QCPlugInContext>)context
{
}

- (void) stopExecution:(id<QCPlugInContext>)context
{
	if (L) {
		lua_close(L);
		
		L	= nil;
	}
}

@end
