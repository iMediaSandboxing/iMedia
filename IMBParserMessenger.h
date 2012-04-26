/*
 iMedia Browser Framework <http://karelia.com/imedia/>
 
 Copyright (c) 2005-2012 by Karelia Software et al.
 
 iMedia Browser is based on code originally developed by Jason Terhorst,
 further developed for Sandvox by Greg Hulands, Dan Wood, and Terrence Talbot.
 The new architecture for version 2.0 was developed by Peter Baumgartner.
 Contributions have also been made by Matt Gough, Martin Wennerberg and others
 as indicated in source files.
 
 The iMedia Browser Framework is licensed under the following terms:
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in all or substantial portions of the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to permit
 persons to whom the Software is furnished to do so, subject to the following
 conditions:
 
	Redistributions of source code must retain the original terms stated here,
	including this list of conditions, the disclaimer noted below, and the
	following copyright notice: Copyright (c) 2005-2012 by Karelia Software et al.
 
	Redistributions in binary form must include, in an end-user-visible manner,
	e.g., About window, Acknowledgments window, or similar, either a) the original
	terms stated here, including this list of conditions, the disclaimer noted
	below, and the aforementioned copyright notice, or b) the aforementioned
	copyright notice and a link to karelia.com/imedia.
 
	Neither the name of Karelia Software, nor Sandvox, nor the names of
	contributors to iMedia Browser may be used to endorse or promote products
	derived from the Software without prior and express written permission from
	Karelia Software or individual contributors, as appropriate.
 
 Disclaimer: THE SOFTWARE IS PROVIDED BY THE COPYRIGHT OWNER AND CONTRIBUTORS
 "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
 AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH, THE
 SOFTWARE OR THE USE OF, OR OTHER DEALINGS IN, THE SOFTWARE.
*/


// Author: Peter Baumgartner


//----------------------------------------------------------------------------------------------------------------------


#pragma mark HEADERS

#import "IMBCommon.h"


//----------------------------------------------------------------------------------------------------------------------


#pragma mark CLASSES

@class IMBNode;
@class IMBObject;
@class IMBParser;
//@class XPCConnection;


//----------------------------------------------------------------------------------------------------------------------


// Lightweight class that lives on both the host app and the XPC service side. Instances of this class can  
// be archived and sent over an XPC connection.  This class basically ties both sides (app and XPC service) 
// together and communicates knowledge (class type) and state (instance properties)...

@interface IMBParserMessenger : NSObject <NSCoding,NSCopying>
{
	NSString* _mediaType;
	NSURL* _mediaSource;
	BOOL _isUserAdded;
	id _connection;
}

// Properties that uniquely define each factory...

+ (NSString*) mediaType;									// See IMBCommon.h for available types
+ (NSString*) parserClassName;								// For instantiating parsers
+ (NSString*) identifier;									// Used in delegate methods

@property (copy) NSString* mediaType;						// See IMBCommon.h for available types
@property (retain) NSURL* mediaSource;						// Source of given media objects
@property BOOL isUserAdded;									// User added items can also be removed by the user again

// For communicating with the XPC service...

+ (NSString*) xpcSerivceIdentifier;							// For connecting to correct XPC service
@property (retain,readonly) id connection;                  // Used internally (XPCConnection)

@end


//----------------------------------------------------------------------------------------------------------------------


// The following methods are only called from an XPC service process...

@interface IMBParserMessenger (XPC)

// This factory method creates IMBParser instances. Usually just returns a single instance, but subclasses  
// may opt to return more than one instance (e.g. Aperture may create one instance per library). MUST be 
// overridden by subclasses..

- (NSArray*) parserInstancesWithError:(NSError**)outError;

// Convenience method to access (potentially also create) a particular parser instance. Should NOT be over-
// ridden in subclasses...

- (IMBParser*) parserWithIdentifier:(NSString*)inIdentifier;

// Factory method for instantiating a single parser. Should NOT be over ridden in subclasses..

- (IMBParser*) newParser;

// The following four methods correspond to the ones in the IMBParser. Here the work is simply 
// delegated to the appropriate IMBParser instance. Should NOT be overridden in subclasses...

- (NSMutableArray*) unpopulatedTopLevelNodes:(NSError**)outError;
- (IMBNode*) populateNode:(IMBNode*)inNode error:(NSError**)outError;
- (IMBNode*) reloadNodeTree:(IMBNode*)inNode error:(NSError**)outError;

// Loads thumbnail (CGImageRef) and metadata (NSDictionary) for a given object. Should NOT be overridden in subclasses...

- (IMBObject*) loadThumbnailForObject:(IMBObject*)inObject error:(NSError**)outError;
- (IMBObject*) loadMetadataForObject:(IMBObject*)inObject error:(NSError**)outError;
- (IMBObject*) loadThumbnailAndMetadataForObject:(IMBObject*)inObject error:(NSError**)outError;

// Creates a security scoped bookmark for accessing the media file in the non-privilegded app process...

- (NSData*) bookmarkForObject:(IMBObject*)inObject error:(NSError**)outError;

@end


//----------------------------------------------------------------------------------------------------------------------


// The following methods are only called by the iMedia framework from the host application process...

@interface IMBParserMessenger (App)

// Called when the user right-clicks in the iMedia UI. Here the IMBParserMessenger has a chance to add custom   
// menu items of its own, that go beyond the functionality of the standard items added by the controllers.
// These methods are only called on the host app side...

- (void) willShowContextMenu:(NSMenu*)ioMenu forNode:(IMBNode*)inNode;
- (void) willShowContextMenu:(NSMenu*)ioMenu forObject:(IMBObject*)inObject;

// Nodes that do not want the standard object views can use custom user intefaces. The following methods   
// provide the mechanics of creating custom view controllers Subclasses should override them to return an   
// appropriate view controller. These methods are only called on the host app side...

- (NSViewController*) customHeaderViewControllerForNode:(IMBNode*)inNode;
- (NSViewController*) customObjectViewControllerForNode:(IMBNode*)inNode;
- (NSViewController*) customFooterViewControllerForNode:(IMBNode*)inNode;

//- (BOOL) shouldDisplayObjectViewForNode:(IMBNode*)inNode;	

// Convert metadata dictionary into human readable form...

- (NSString*) metadataDescriptionForMetadata:(NSDictionary*)inMetadata;

//- (IMBNode*) nodeWithIdentifier:(NSString*)inIdentifier;
//- (void) invalidateThumbnails;

@end


//----------------------------------------------------------------------------------------------------------------------

