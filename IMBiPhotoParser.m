/*
 iMedia Browser Framework <http://karelia.com/imedia/>
 
 Copyright (c) 2005-2011 by Karelia Software et al.
 
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
	following copyright notice: Copyright (c) 2005-2011 by Karelia Software et al.

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


// Author: Peter Baumgartner, Jörg Jacobsen


//----------------------------------------------------------------------------------------------------------------------


#pragma mark HEADERS

#import "IMBiPhotoParser.h"
#import "IMBConfig.h"
#import "IMBParserController.h"
#import "IMBiPhotoEventObjectViewController.h"
#import "IMBImageViewController.h"
#import "IMBNode.h"
#import "IMBObject.h"
#import "IMBiPhotoEventNodeObject.h"
#import "IMBIconCache.h"
#import "NSWorkspace+iMedia.h"
#import "NSFileManager+iMedia.h"
#import "NSImage+iMedia.h"
#import "NSString+iMedia.h"
#import <Quartz/Quartz.h>


//----------------------------------------------------------------------------------------------------------------------

// Since we will add an events node to the list of albums we have to create an id for it
// that is unique throughout this library. The one chosen below is very, very likely to be.
// Actually checking uniqueness would require us to traverse different arrays and would
// not necessarily be future proof (e.g. if we'd once add 'faces' to the browser
// we'd also have to check against faces ids).

#define EVENTS_NODE_ID UINT_MAX-4811	// Very, very unlikely this not to be unique throughout library

// We are not a 100 % sure whether event ids and album ids are from the same id space.
// Since we use both kinds of ids in the same tree we introduce id space identifiers to the rescue.

#define EVENTS_ID_SPACE @"EventId"
#define ALBUMS_ID_SPACE @"AlbumId"

#pragma mark CONSTANTS

// node object types of interest for skimming

NSString* kIMBiPhotoNodeObjectTypeEvent = @"events";
NSString* kIMBiPhotoNodeObjectTypeFace  = @"faces";
//----------------------------------------------------------------------------------------------------------------------

#pragma mark 

@interface IMBiPhotoParser ()

- (void) addEventsToAlbumsInLibrary:(NSMutableDictionary*)inDict;
- (BOOL) isEventsNode:(IMBNode*)inNode;
- (IMBNode*) eventsNodeInNode:(IMBNode*)inNode;
- (NSString*) idSpaceForAlbumType:(NSString*)inAlbumType;
- (NSString*) identifierForId:(NSNumber*)inId inSpace:(NSString*)inIdSpace;
- (NSString*) iPhotoMediaType;
- (BOOL) shouldUseAlbumType:(NSString*)inAlbumType;
- (BOOL) shouldUseAlbum:(NSDictionary*)inAlbumDict images:(NSDictionary*)inImages;
- (BOOL) shouldUseObject:(NSDictionary*)inObjectDict;
- (NSImage*) iconForAlbumType:(NSString*)inAlbumType;
- (BOOL) isLeafAlbumType:(NSString*)inAlbumType;
- (NSString*) imagePathForImageKey:(NSString*)inImageKey;
- (void) addSubNodesToNode:(IMBNode*)inParentNode albums:(NSArray*)inAlbums images:(NSDictionary*)inImages;
- (void) populateEventsNode:(IMBNode*)inNode withEvents:(NSArray*)inEvents images:(NSDictionary*)inImages;
- (void) populateAlbumNode:(IMBNode*)inNode images:(NSDictionary*)inImages;
- (NSString*) metadataDescriptionForMetadata:(NSDictionary*)inMetadata;

@end


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 

@implementation IMBiPhotoParser

@synthesize appPath = _appPath;
@synthesize plist = _plist;
@synthesize modificationDate = _modificationDate;
@synthesize shouldDisplayLibraryName = _shouldDisplayLibraryName;
@synthesize dateFormatter = _dateFormatter;


//----------------------------------------------------------------------------------------------------------------------


// Register this parser, so that it gets automatically loaded...

+ (void) load
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[IMBParserController registerParserClass:self forMediaType:kIMBMediaTypeImage];
	[pool drain];
}


//----------------------------------------------------------------------------------------------------------------------


// Check if iPhoto is installed...

+ (NSString*) iPhotoPath
{
	return [[NSWorkspace imb_threadSafeWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.iPhoto"];
}


+ (BOOL) isInstalled
{
	return [self iPhotoPath] != nil;
}


//----------------------------------------------------------------------------------------------------------------------


+ (NSString*) objectCountFormatSingular
{
	return [IMBImageViewController objectCountFormatSingular];
}


+ (NSString*) objectCountFormatPlural
{
	return [IMBImageViewController objectCountFormatPlural];
}


//----------------------------------------------------------------------------------------------------------------------


// Look at the iApps preferences file and find all iPhoto libraries. Create a parser instance for each libary...

+ (NSArray*) parserInstancesForMediaType:(NSString*)inMediaType
{
	NSMutableArray* parserInstances = [NSMutableArray array];
	
	if ([self isInstalled])
	{
		CFArrayRef recentLibraries = CFPreferencesCopyAppValue((CFStringRef)@"iPhotoRecentDatabases",(CFStringRef)@"com.apple.iApps");
		NSArray* libraries = (NSArray*)recentLibraries;
		
		for (NSString* library in libraries)
		{
			NSURL* url = [NSURL URLWithString:library];
			NSString* path = [url path];
			BOOL changed;
			
			if ([[NSFileManager imb_threadSafeManager] imb_fileExistsAtPath:&path wasChanged:&changed])
			{
				NSString *libraryPath = [path stringByDeletingLastPathComponent];	// folder containing .xml file
				[IMBConfig registerLibraryPath:libraryPath];
			
				IMBiPhotoParser* parser = [[[self class] alloc] initWithMediaType:inMediaType];
				parser.mediaSource = path;
				parser.shouldDisplayLibraryName = libraries.count > 1;
				[parserInstances addObject:parser];
				[parser release];
			}
		}
		
		if (recentLibraries) CFRelease(recentLibraries);
	}
	
	return parserInstances;
}


- (Class) objectClass
{
	return [IMBObject class];
}


//----------------------------------------------------------------------------------------------------------------------


- (id) initWithMediaType:(NSString*)inMediaType
{
	if (self = [super initWithMediaType:inMediaType])
	{
		self.appPath = [[self class] iPhotoPath];
		self.plist = nil;
		self.modificationDate = nil;
		_fakeAlbumID = 0;
		
		self.dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
		self.dateFormatter.dateStyle = NSDateFormatterShortStyle;
	}
	
	return self;
}


- (void) dealloc
{
	IMBRelease(_appPath);
	IMBRelease(_plist);
	IMBRelease(_modificationDate);
	IMBRelease(_dateFormatter);
	[super dealloc];
}


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 
#pragma mark Parser Methods

- (IMBNode*) nodeWithOldNode:(const IMBNode*)inOldNode options:(IMBOptions)inOptions error:(NSError**)outError
{
	NSError* error = nil;
	
	// Oops no path, can't create a root node. This is bad...
	
	NSString* path = (NSString*)self.mediaSource;
	
	if (path == nil)
	{
		return nil;
	}
	
	if ([[NSFileManager imb_threadSafeManager] fileExistsAtPath:path] == NO)
	{
		return nil;
	}
	
	// Create a root node...
	
	IMBNode* node = [[[IMBNode alloc] init] autorelease];
	
	if (inOldNode == nil)
	{
		NSImage* icon = [[NSWorkspace imb_threadSafeWorkspace] iconForFile:self.appPath];;
		[icon setScalesWhenResized:YES];
		[icon setSize:NSMakeSize(16.0,16.0)];
		
		node.mediaSource = self.mediaSource;
		node.identifier = [self identifierForPath:@"/"];
		node.name = @"iPhoto";
		node.icon = icon;
		node.groupType = kIMBGroupTypeLibrary;
		node.leaf = NO;
		node.parser = self;
		node.isTopLevelNode = YES;
	}
	
	// Or an subnode...
	
	else
	{
		node.mediaSource = self.mediaSource;
		node.identifier = inOldNode.identifier;
		node.name = inOldNode.name;
		node.icon = inOldNode.icon;
		node.groupType = inOldNode.groupType;
		node.leaf = inOldNode.leaf;
		node.parser = self;
		node.attributes = inOldNode.attributes;
	}
	
	// If we have more than one library then append the library name to the root node...
	
	if (node.isTopLevelNode && self.shouldDisplayLibraryName)
	{
		NSString* path = (NSString*)node.mediaSource;
		NSString* name = [[[path stringByDeletingLastPathComponent] lastPathComponent] stringByDeletingPathExtension];
		node.name = [NSString stringWithFormat:@"%@ (%@)",node.name,name];
	}
	
	// Watch the XML file. Whenever something in iPhoto changes, we have to replace the WHOLE tree from  
	// the root node down, as we have no way of finding WHAT has changed in iPhoto...
	
	if (node.isTopLevelNode)
	{
		node.watcherType = kIMBWatcherTypeFSEvent;
		node.watchedPath = [(NSString*)node.mediaSource stringByDeletingLastPathComponent];
	}
	else
	{
		node.watcherType = kIMBWatcherTypeNone;
	}
	
	// If the old node was populated, then also populate the new node...
	
	if (inOldNode.isPopulated)
	{
		[self populateNewNode:node likeOldNode:inOldNode options:inOptions];
	}
	
	if (outError) *outError = error;
	return node;
}


//----------------------------------------------------------------------------------------------------------------------


// The supplied node is a private copy which may be modified here in the background operation. Parse the 
// iPhoto XML file and create subnodes as needed...

- (BOOL) populateNode:(IMBNode*)inNode options:(IMBOptions)inOptions error:(NSError**)outError
{
	NSError* error = nil;
	NSDictionary* plist = self.plist;
	NSDictionary* images = [plist objectForKey:@"Master Image List"];
	
	// Population of events node fundamentally different from album node
	
	if ([self isEventsNode:inNode]) {
		NSArray* events = [plist objectForKey:@"List of Rolls"];
		[self populateEventsNode:inNode withEvents:events images:images];
	} else {
		NSArray* albums = [plist objectForKey:@"List of Albums"];
		[self addSubNodesToNode:inNode albums:albums images:images]; 
		[self populateAlbumNode:inNode images:images]; 
	}

	// If we are populating the root nodes, then also populate the "Photos" node (second subnode) and mirror its
	// objects array into the objects array of the root node. Please note that this is non-standard parser behavior,
	// which is implemented here, to achieve the desired "feel" in the browser...
	
	NSArray* subNodes = inNode.subNodes;
	
	if (inNode.isTopLevelNode && [subNodes count] > 0)
	{
		IMBNode* eventsNode = [self eventsNodeInNode:inNode];
		
		// Depending on whether there is an events node or not and
		// depending on where it's located
		// we find photos node at a different index
		int photosNodeIndex = eventsNode &&
		eventsNode == [subNodes objectAtIndex:0] &&
		[subNodes count] > 1 ? 1 : 0;
		
		IMBNode* photosNode = [subNodes objectAtIndex:photosNodeIndex];
		[self populateNode:photosNode options:inOptions error:outError];
		inNode.objects = photosNode.objects;
	}
	
	if (outError) *outError = error;
	return error == nil;
}


//----------------------------------------------------------------------------------------------------------------------


// When the parser is deselected, then get rid of the cached plist data. It will be loaded into memory lazily 
// once it is needed again...

- (void) didStopUsingParser
{
	@synchronized(self)
	{
		self.plist = nil;
	}	
}


// When the XML file has changed then get rid of our cached plist...

- (void) watchedPathDidChange:(NSString*)inWatchedPath
{
	if ([inWatchedPath isEqual:self.mediaSource])
	{
		@synchronized(self)
		{
			self.plist = nil;
		}	
	}
}


//----------------------------------------------------------------------------------------------------------------------


// To speed up thumbnail loading we will not use the generic method of the superclass. Instead we provide an
// implementation here, that uses specific knowledge about iPhoto to load thumbnails as quickly as possible...

- (id) loadThumbnailForObject:(IMBObject*)inObject
{
	id imageRepresentation = nil;
	
	// Get path of our object...
	
	NSString* type = inObject.imageRepresentationType;
	NSString* path = (NSString*) inObject.imageLocation;
	if (path == nil) path = (NSString*) inObject.location;
	
	// For images we provide an optimized loading code...
	
	NSURL* url = [NSURL fileURLWithPath:path];
	NSString* uti = [NSString imb_UTIForFileAtPath:path];
	
	if ([type isEqualToString:IKImageBrowserCGImageRepresentationType])
	{
		if (UTTypeConformsTo((CFStringRef)uti,kUTTypeImage))
		{
			NSAssert(url, @"Nil image source URL");
			CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url,NULL);
			
			if (source)
			{
				CGImageRef image = CGImageSourceCreateImageAtIndex(source,0,NULL);
				
				if (image)
				{
					imageRepresentation = (id) image;
					[inObject 
					 performSelectorOnMainThread:@selector(setImageRepresentation:) 
					 withObject:(id)image
					 waitUntilDone:NO 
					 modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
					
					CGImageRelease(image);
				}
				
				CFRelease(source);
			}
			
		}
	}
	
	// QTMovies are loaded with the generic code in the superclass...
	
	else if ([type isEqualToString:IKImageBrowserQTMoviePathRepresentationType])
	{
		imageRepresentation = [super loadThumbnailForObject:inObject];
	}
	
	return imageRepresentation;
}


//----------------------------------------------------------------------------------------------------------------------


// Loaded lazily when actually needed for display. Here we combine the metadata we got from the iPhoto XML file
// (which was available immediately, but not enough information) with more information that we obtain via ImageIO.
// This takes a little longer, but since it only done laziy for those object that are actually visible it's fine.
// Please note that this method may be called on a background thread...

- (void) loadMetadataForObject:(IMBObject*)inObject
{
	NSMutableDictionary* metadata = [NSMutableDictionary dictionaryWithDictionary:inObject.preliminaryMetadata];
	NSMutableArray *realKeywords = [NSMutableArray array];
	
	NSDictionary *keywordMap = [self.plist objectForKey:@"List of Keywords"];

	//swap the keyword index to names
	for (NSString *keywordKey in [metadata objectForKey:@"Keywords"])
	{
		NSString *actualKeyword = [keywordMap objectForKey:keywordKey];
		if (actualKeyword)
		{
			[realKeywords addObject:actualKeyword];
		}
		[metadata setObject:realKeywords forKey:@"iMediaKeywords"];
	}
	
	// Do not load (key) image specific metadata for node objects
	// because it doesn't represent the nature of the object well enough.
	
	if (![inObject isKindOfClass:[IMBNodeObject class]])
	{
		[metadata addEntriesFromDictionary:[NSImage imb_metadataFromImageAtPath:inObject.path checkSpotlightComments:NO]];
	}
	NSString* description = [self metadataDescriptionForMetadata:metadata];

	if ([NSThread isMainThread])
	{
		inObject.metadata = metadata;
		inObject.metadataDescription = description;
	}
	else
	{
		NSArray* modes = [NSArray arrayWithObject:NSRunLoopCommonModes];
		[inObject performSelectorOnMainThread:@selector(setMetadata:) withObject:metadata waitUntilDone:NO modes:modes];
		[inObject performSelectorOnMainThread:@selector(setMetadataDescription:) withObject:description waitUntilDone:NO modes:modes];
	}
}


// Events have other metadata than images or movies

- (NSString*) eventMetadataDescriptionForMetadata:(NSDictionary*)inMetadata
{
	NSMutableString* metaDesc = [NSMutableString string];
	
	NSNumber* count = [inMetadata objectForKey:@"PhotoCount"];
	if (count)
	{
		NSString* formatString = [count intValue] > 1 ?
		[[self class] objectCountFormatPlural] :
		[[self class] objectCountFormatSingular];
		
		[metaDesc appendFormat:formatString, [count intValue]];
	}
	
	NSNumber* dateAsTimerInterval = [inMetadata objectForKey:@"RollDateAsTimerInterval"];
	if (dateAsTimerInterval)
	{
		[metaDesc imb_appendNewline];
		NSDate* eventDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[dateAsTimerInterval doubleValue]];
		
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
		[formatter setDateStyle:NSDateFormatterMediumStyle];	// medium date
		
		[metaDesc appendFormat:@"%@", [formatter stringFromDate:eventDate]];
		
		[formatter release];
	}
	return metaDesc;
}


- (NSString*) metadataDescriptionForMetadata:(NSDictionary*)inMetadata
{
	// Events have other metadata than images
	
	if ([inMetadata objectForKey:@"RollID"])		// Event
	{
		return [self eventMetadataDescriptionForMetadata:inMetadata];
	}
	
	// Image
	return [NSImage imb_imageMetadataDescriptionForMetadata:inMetadata];
}


- (NSArray *)iMediaKeywordsFromIDs:(NSArray *)keywordIDs
{
	NSMutableArray *realKeywords = [NSMutableArray array];
	NSDictionary *keywordMap = [self.plist objectForKey:@"List of Keywords"];
	//swap the keyword index to names
	for (NSString *keywordKey in keywordIDs)
	{
		NSString *actualKeyword = [keywordMap objectForKey:keywordKey];
		if (actualKeyword)
		{
			[realKeywords addObject:actualKeyword];
		}
	}
	return realKeywords;
}


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 
#pragma mark Custom view controller support

- (NSViewController*) customObjectViewControllerForNode:(IMBNode*)inNode
{
	// Use custom view for events
	
    if ([self isEventsNode:inNode])
	{
		NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  kIMBiPhotoNodeObjectTypeEvent, @"nodeObjectType", nil];

		return [[[IMBiPhotoEventObjectViewController alloc] initWithDelegate:self userInfo:userInfo] autorelease];;
	}
	
	return [super customObjectViewControllerForNode:inNode];
}


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 
#pragma mark Skimmable object view controller delegate

- (NSUInteger) childrenCountOfNodeObject:(IMBNodeObject*)inNodeObject userInfo:(NSDictionary*)inUserInfo
{
	return [[inNodeObject.preliminaryMetadata objectForKey:@"PhotoCount"] integerValue];
}


- (NSString*) imagePathForChildOfNodeObject:(IMBNodeObject*)inNodeObject atIndex:(NSUInteger)inIndex userInfo:(NSDictionary*)inUserInfo
{
	NSString* imageKey = [[inNodeObject.preliminaryMetadata objectForKey:@"KeyList"] objectAtIndex:inIndex];
	
	return [self imagePathForImageKey:imageKey];
}


- (NSString*) imagePathForKeyChildOfNodeObject:(IMBNodeObject*)inNodeObject userInfo:(NSDictionary*)inUserInfo
{
	NSString* imageKey = [inNodeObject.preliminaryMetadata objectForKey:@"KeyPhotoKey"];
	
	return [self imagePathForImageKey:imageKey];
}


#pragma mark 
#pragma mark Helper Methods


// Load the XML file into a plist lazily (on demand). If we notice that an existing cached plist is out-of-date 
// we get rid of it and load it anew...

- (NSDictionary*) plist
{
	NSDictionary* result = nil;
	NSError* error = nil;
	NSString* path = (NSString*)self.mediaSource;
	
	if ([[NSFileManager imb_threadSafeManager] fileExistsAtPath:path])
	{
		NSDictionary* metadata = [[NSFileManager imb_threadSafeManager] attributesOfItemAtPath:path error:&error];
		NSDate* modificationDate = [metadata objectForKey:NSFileModificationDate];
			
		@synchronized(self)
		{
			if ([self.modificationDate compare:modificationDate] == NSOrderedAscending)
			{
				self.plist = nil;
			}
			
			if (_plist == nil)
			{
				// Since we want to add events to the list of albums we will need
				// to modify the album data dictionary (see further down below)
				NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
				
				// WORKAROUND
				if (dict == nil || 0 == dict.count)	// unable to read. possibly due to unencoded '&'.  rdar://7469235
				{
					NSData *data = [NSData dataWithContentsOfFile:path];
					if (data)
					{
						NSString *eString = nil;
						NSError *e = nil;
						@try
						{
							NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:data
																				options:NSXMLDocumentTidyXML error:&e];
							dict = [NSPropertyListSerialization
								  propertyListFromData:[xmlDoc XMLData]
								  mutabilityOption:0					// Apple doc: The opt parameter is currently unused and should be set to 0.
								  format:NULL errorDescription:&eString];
							[xmlDoc release];
							
							// the assignment to 'dict' in the code above yields
							// a mutable dictionary as this code snippet would reveal:
							// Class dictClass = [dict classForCoder];
							// NSLog(@"Dictionary class: %@", [dictClass description]);
						}
						@catch(NSException *e)
						{
							NSLog(@"%s %@", __FUNCTION__, e);
						}
						// When we start targetting 10.6, we should use propertyListWithData:options:format:error:
					}
				}			
				
				//	If there is an AlbumData.xml file, there should be something inside!

				if (dict == nil || 0 == dict.count)
				{
					NSLog (@"The iPhoto AlbumData.xml file seems to be empty. This is an unhealthy condition!");
				}
				
				// Since this parser confines itself to deal with the "List of Albums" only
				// we add an events node to the album list to incorporate events in the browser.
				// This is why we need a mutable library dictionary.

				if (dict)
				{
					[self addEventsToAlbumsInLibrary:dict];
				}
				
				self.plist = dict;
				self.modificationDate = modificationDate;
			}
			
			result = [[_plist retain] autorelease];
		}
	}
		
	return result;
}



//----------------------------------------------------------------------------------------------------------------------

// iPhoto does not include events in the album list. To let events also be shown
// in the browser we let events (aka rolls) pose as albums in the album list
// an let them be children of an 'events' node that we also add to the album list.

- (void) addEventsToAlbumsInLibrary:(NSMutableDictionary*)inDict
{	
	NSArray* eventList = [inDict objectForKey:@"List of Rolls"];		
	NSArray* oldAlbumList = [inDict objectForKey:@"List of Albums"];		

	if (eventList != nil && oldAlbumList != nil && [oldAlbumList count]>0)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		
		// To insert events into the album list we have to re-create it mutable style
		NSMutableArray *newAlbumList = [[NSMutableArray alloc] init];
		
		// 1. We want the events node to be first in the list
		// Create and append parent object for all events.
		
		NSNumber *eventsId = [NSNumber numberWithUnsignedInt:EVENTS_NODE_ID];
		NSString *eventsName = NSLocalizedStringWithDefaultValue(@"IMB.iPhotoParser.events", nil, IMBBundle(), @"Events", @"Events node shown in iPhoto library");
		
		NSDictionary *photosDict = [oldAlbumList objectAtIndex:0];	// Photos node
		id keyList = [photosDict objectForKey:@"KeyList"];
		
		if (keyList != nil)
		{
			NSDictionary* events = [[NSDictionary alloc] initWithObjectsAndKeys:
				eventsId,@"AlbumId",
				eventsName,@"AlbumName",
				@"Events",@"Album Type",
				keyList,@"KeyList", nil];   // populate events with same media objects as photos album
			
			[newAlbumList addObject:events];
			IMBRelease(events);
			
			// 2. Append all regular albums. Note that the photos album will now be at index 1 of the list
			[newAlbumList addObjectsFromArray:oldAlbumList];
			
			// Finally, replace the old albums array.
			[inDict setValue:newAlbumList forKey:@"List of Albums"];
		}
		[newAlbumList release];
		[pool drain];
	}
}


//----------------------------------------------------------------------------------------------------------------------

// Returns whether inNode is the events node

- (BOOL) isEventsNode:(IMBNode*)inNode
{	
	NSNumber* eventsId = [NSNumber numberWithUnsignedInt:EVENTS_NODE_ID];
	NSString* eventsIdentifier = [self identifierForId:eventsId inSpace:EVENTS_ID_SPACE];
	
	return [inNode.identifier isEqualToString:eventsIdentifier];
}


//----------------------------------------------------------------------------------------------------------------------

// Returns the events node that should be subnode of our root node.
// Returns nil if there is none.

- (IMBNode*) eventsNodeInNode:(IMBNode*) inNode
{	
	IMBNode* eventsNode = nil;
	
	if (inNode.isTopLevelNode && [inNode.subNodes count]>0) {
		
		// We should find the events node at index 0 but this logic is more bullet proof.
		
		for (IMBNode* node in inNode.subNodes) {
			
			if ([self isEventsNode:node]) {
				eventsNode = node;
				break;
			}
		}
	}
	
	return eventsNode;
}


//----------------------------------------------------------------------------------------------------------------------


// This media type is specific to iPhoto and is not to be confused with kIMBMediaTypeImage...

- (NSString*) iPhotoMediaType
{
	return @"Image";
}


//----------------------------------------------------------------------------------------------------------------------

// Use different id spaces for entries in "List of Albums" and "List of Rolls" (events):
// Returns events id space for album types "Event" and "Events".
// Otherwise returns albums id space.
// Use preproc defines in this file to compare against.

- (NSString*) idSpaceForAlbumType:(NSString*) inAlbumType
{
	if ([inAlbumType isEqualToString:@"Event"] || [inAlbumType isEqualToString:@"Events"]) {
		return EVENTS_ID_SPACE;
	}
	return ALBUMS_ID_SPACE;
}

//----------------------------------------------------------------------------------------------------------------------

// Create an identifier from the AlbumID that is stored in the XML file. An example is "IMBiPhotoParser://AlbumId/17"...

- (NSString*) identifierForId:(NSNumber*) inId inSpace:(NSString*) inIdSpace
{
	NSString* albumPath = [NSString stringWithFormat:@"/%@/%@", inIdSpace, inId];
	return [self identifierForPath:albumPath];
}


//----------------------------------------------------------------------------------------------------------------------


// Exclude some album types...

- (BOOL) shouldUseAlbumType:(NSString*)inAlbumType
{
	if (inAlbumType == nil) return YES;
	if ([inAlbumType isEqualToString:@"Slideshow"]) return NO;
	if ([inAlbumType isEqualToString:@"Book"]) return NO;
	return YES;
}


// Check if the supplied album contains media files of correct media type. If we find a single one, then the 
// album qualifies as a new node. If however we do not find any media files of the desired type, then the 
// album will not show up as a node...

- (BOOL) shouldUseAlbum:(NSDictionary*)inAlbumDict images:(NSDictionary*)inImages
{
	NSArray* imageKeys = [inAlbumDict objectForKey:@"KeyList"];
	
	for (NSString* key in imageKeys)
	{
		NSDictionary* imageDict = [inImages objectForKey:key];
		
		if ([self shouldUseObject:imageDict])
		{
			return YES;
		}
	}
	
	return NO;
}


// Check if a media file qualifies for this parser...

- (BOOL) shouldUseObject:(NSDictionary*)inObjectDict
{
	NSString* iPhotoMediaType = [self iPhotoMediaType];
	
	if (inObjectDict)
	{
		NSString* mediaType = [inObjectDict objectForKey:@"MediaType"];
		if (mediaType == nil) mediaType = @"Image";
		
		if ([mediaType isEqualToString:iPhotoMediaType])
		{
			return YES;
		}
	}
	
	return NO;
}


//----------------------------------------------------------------------------------------------------------------------


- (NSImage*) iconForAlbumType:(NSString*)inAlbumType
{
	static const IMBIconTypeMappingEntry kIconTypeMappingEntries[] =
	{
		// iPhoto 7
		{@"Book",					@"sl-icon-small_book.tiff",				@"folder",	nil,				nil},
		{@"Calendar",				@"sl-icon-small_calendar.tiff",			@"folder",	nil,				nil},
		{@"Card",					@"sl-icon-small_card.tiff",				@"folder",	nil,				nil},
		{@"Event",					@"sl-icon-small_event.tiff",			@"folder",	nil,				nil},
		{@"Events",					@"sl-icon-small_events.tiff",			@"folder",	nil,				nil},
		{@"Folder",					@"sl-icon-small_folder.tiff",			@"folder",	nil,				nil},
		{@"Photocasts",				@"sl-icon-small_subscriptions.tiff",	@"folder",	nil,				nil},
		{@"Photos",					@"sl-icon-small_library.tiff",			@"folder",	nil,				nil},
		{@"Published",				@"sl-icon-small_publishedAlbum.tiff",	nil,		@"dotMacLogo.icns",	@"/System/Library/CoreServices/CoreTypes.bundle"},
		{@"Regular",				@"sl-icon-small_album.tiff",			@"folder",	nil,				nil},
		{@"Roll",					@"sl-icon-small_roll.tiff",				@"folder",	nil,				nil},
		{@"Selected Event Album",	@"sl-icon-small_event.tiff",			@"folder",	nil,				nil},
		{@"Shelf",					@"sl-icon_flag.tiff",					@"folder",	nil,				nil},
		{@"Slideshow",				@"sl-icon-small_slideshow.tiff",		@"folder",	nil,				nil},
		{@"Smart",					@"sl-icon-small_smartAlbum.tiff",		@"folder",	nil,				nil},
		{@"Special Month",			@"sl-icon-small_cal.tiff",				@"folder",	nil,				nil},
		{@"Special Roll",			@"sl-icon_lastImport.tiff",				@"folder",	nil,				nil},
		{@"Subscribed",				@"sl-icon-small_subscribedAlbum.tiff",	@"folder",	nil,				nil},
	};
	
	static const IMBIconTypeMapping kIconTypeMapping =
	{
		sizeof(kIconTypeMappingEntries) / sizeof(kIconTypeMappingEntries[0]),
		kIconTypeMappingEntries,
		{@"Regular",				@"sl-icon-small_album.tiff",			@"folder",	nil,				nil}	// fallback image
	};
	
	NSString* type = inAlbumType;
	if (type == nil) type = @"Photos";
	return [[IMBIconCache sharedIconCache] iconForType:type fromBundleID:@"com.apple.iPhoto" withMappingTable:&kIconTypeMapping];
}


//----------------------------------------------------------------------------------------------------------------------


- (BOOL) isLeafAlbumType:(NSString*)inType
{
	return ![inType isEqualToString:@"Folder"] && ![inType isEqualToString:@"Events"];
}


//----------------------------------------------------------------------------------------------------------------------


- (void) addSubNodesToNode:(IMBNode*)inParentNode albums:(NSArray*)inAlbums images:(NSDictionary*)inImages
{
	// Create the subNodes array on demand - even if turns out to be empty after exiting this method, 
	// because without creating an array we would cause an endless loop...
	
	NSMutableArray* subNodes = [NSMutableArray array];
	
	// Now parse the iPhoto XML plist and look for albums whose parent matches our parent node. We are 
	// only going to add subnodes that are direct children of inParentNode...
	
	for (NSDictionary* albumDict in inAlbums)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		
		NSString* albumType = [albumDict objectForKey:@"Album Type"];
		NSString* albumName = [albumDict objectForKey:@"AlbumName"];
		NSNumber* parentId = [albumDict objectForKey:@"Parent"];
		NSString* albumIdSpace = [self idSpaceForAlbumType:albumType];
		// parent always from same id space
		NSString* parentIdentifier = parentId ? [self identifierForId:parentId inSpace:albumIdSpace] : [self identifierForPath:@"/"];
		
		if ([self shouldUseAlbumType:albumType] && 
			[inParentNode.identifier isEqualToString:parentIdentifier] && 
			[self shouldUseAlbum:albumDict images:inImages])
		{
			// Create node for this album...
			
			IMBNode* albumNode = [[[IMBNode alloc] init] autorelease];
			
			albumNode.leaf = [self isLeafAlbumType:albumType];
			albumNode.icon = [self iconForAlbumType:albumType];
			albumNode.name = albumName;
			albumNode.mediaSource = self.mediaSource;
			albumNode.parser = self;
			
			// Keep a ref to the album dictionary for later use when we populate this node
			// so we don't have to loop through the whole album list again to find it.
			
			albumNode.attributes = albumDict;
			
			// Set the node's identifier. This is needed later to link it to the correct parent node. Please note 
			// that older versions of iPhoto didn't have AlbumId, so we are generating fake AlbumIds in this case
			// for backwards compatibility...
			
			NSNumber* albumId = [albumDict objectForKey:@"AlbumId"];
			if (albumId == nil) albumId = [NSNumber numberWithInt:_fakeAlbumID++]; 
			albumNode.identifier = [self identifierForId:albumId inSpace:albumIdSpace];
			
			// Add the new album node to its parent (inRootNode)...
			
			
			[subNodes addObject:albumNode];
		}
		
		[pool drain];
	}
	
	inParentNode.subNodes = subNodes;
}


//----------------------------------------------------------------------------------------------------------------------


// This parser wants image thumbnails...

- (NSString*) requestedImageRepresentationType
{
	return IKImageBrowserCGImageRepresentationType;
}


// Use the path of the small thumbnail file to create this image...

- (NSString*) imageLocationForObject:(NSDictionary*)inObjectDict
{
	return [inObjectDict objectForKey:@"ThumbPath"];
}


- (NSString*) imagePathForImageKey:(NSString*)inImageKey
{
	NSDictionary* images = [[self plist] objectForKey:@"Master Image List"];
	NSDictionary* imageDict = [images objectForKey:inImageKey];
	NSString* imagePath = [self imageLocationForObject:imageDict];
	
	return imagePath; 
}


//---------------------------------------------------------------------------------------------------------------------


// Returns a dictionary that contains the "true" KeyList, KeyPhotoKey and PhotoCount values for the provided event node.
// (The values provided by the according dictionary in .plist are mostly wrong because we separate event children by
// media types Image and Movie respectively into different views.)

- (NSDictionary*) childrenInfoForEventNodeObject:(IMBiPhotoEventNodeObject*)inNodeObject
											node:(IMBNode*)inNode
										  images:(NSDictionary*)inImages
{
	NSMutableArray* relevantImageKeys = [[[NSMutableArray alloc] init] autorelease];
	
	// We saved a reference to the album dictionary when this node was created
	// (ivar 'attributes') and now happily reuse it to save an outer loop (over album list) here.
	
	NSDictionary* albumDict = inNode.attributes;	
	NSArray* imageKeys = [albumDict objectForKey:@"KeyList"];
	
	for (NSString* key in imageKeys)
	{
		NSDictionary* imageDict = [inImages objectForKey:key];
		
		if ([self shouldUseObject:imageDict])
		{
			[relevantImageKeys addObject:key];
		}		
	}
	
	// Key image for movies must be movie related:
	
	NSString* keyPhotoKey;
	if ([[self iPhotoMediaType] isEqualToString:@"Movie"] && [relevantImageKeys count] > 0)
	{
		keyPhotoKey = [relevantImageKeys objectAtIndex:0];
	} else {
		keyPhotoKey = [albumDict objectForKey:@"KeyPhotoKey"];
	}

	
    return [NSDictionary dictionaryWithObjectsAndKeys:
			relevantImageKeys, @"KeyList",
			[NSNumber numberWithUnsignedInteger:[relevantImageKeys count]], @"PhotoCount", 
			keyPhotoKey, @"KeyPhotoKey", nil];
}


//----------------------------------------------------------------------------------------------------------------------


// Create a subnode for each event and a corresponding visual object

- (void) populateEventsNode:(IMBNode*)inNode 
				 withEvents:(NSArray*)inEvents
					 images:(NSDictionary*)inImages
{
	// Create the subNodes array on demand - even if turns out to be empty after exiting this method, 
	// because without creating an array we would cause an endless loop...
	
	NSMutableArray* subNodes = [NSMutableArray array];
	
	// Create the objects array on demand  - even if turns out to be empty after exiting this method, because
	// without creating an array we would cause an endless loop...
	
	NSMutableArray* objects = [[NSMutableArray alloc] initWithArray:inNode.objects];
	
	NSUInteger index = 0;
	
	// We saved a reference to the album dictionary when this node was created
	// (ivar 'attributes') and now happily reuse it to save an outer loop (over album list) here.
	
	NSString* subNodeType = @"Event";
	
	// Events node is populated with node objects that represent events
	
	NSString* eventKeyPhotoKey = nil;
	NSString* path = nil;
	IMBiPhotoEventNodeObject* object = nil;
	
	for (NSDictionary* subNodeDict in inEvents)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

		NSString* subNodeName = [subNodeDict objectForKey:@"RollName"];
		
		if ([self shouldUseAlbumType:subNodeType] && 
			[self shouldUseAlbum:subNodeDict images:inImages])
		{
			// Create subnode for this node...
			
			IMBNode* subNode = [[[IMBNode alloc] init] autorelease];
			
			subNode.leaf = [self isLeafAlbumType:subNodeType];
			subNode.icon = [self iconForAlbumType:subNodeType];
			subNode.name = subNodeName;
			subNode.mediaSource = self.mediaSource;
			subNode.parser = self;
			
			// Keep a ref to the subnode dictionary for later use when we populate this node
			// so we don't have to loop through the whole album list again to find it.
			
			subNode.attributes = subNodeDict;
			
			// Set the node's identifier. This is needed later to link it to the correct parent node. Please note 
			// that older versions of iPhoto didn't have AlbumId, so we are generating fake AlbumIds in this case
			// for backwards compatibility...
			
			NSNumber* subNodeId = [subNodeDict objectForKey:@"RollID"];
			if (subNodeId == nil) subNodeId = [NSNumber numberWithInt:_fakeAlbumID++]; 
			subNode.identifier = [self identifierForId:subNodeId inSpace:EVENTS_ID_SPACE];
			
			// Add the new subnode to its parent (inRootNode)...

			[subNodes addObject:subNode];
			
			// Now create the visual object and link it to subnode just created

			object = [[IMBiPhotoEventNodeObject alloc] init];
			[objects addObject:object];
			[object release];
			
			// Adjust keys "KeyPhotoKey", "KeyList", and "PhotoCount" in metadata dictionary
			// because movies and images are not jointly displayed in iMedia browser
			NSMutableDictionary* preliminaryMetadata = [NSMutableDictionary dictionaryWithDictionary:subNodeDict];
			[preliminaryMetadata addEntriesFromDictionary:[self childrenInfoForEventNodeObject:object
																						  node:subNode
																						images:inImages]];

			object.preliminaryMetadata = preliminaryMetadata;	// This metadata from the XML file is available immediately
			object.metadata = nil;								// Build lazily when needed (takes longer)
			object.metadataDescription = nil;					// Build lazily when needed (takes longer)
			
			// Obtain key photo dictionary (key photo is displayed while not skimming)
			eventKeyPhotoKey = [object.preliminaryMetadata objectForKey:@"KeyPhotoKey"];
			NSDictionary* keyPhotoDict = [inImages objectForKey:eventKeyPhotoKey];
			
			path = [keyPhotoDict objectForKey:@"ImagePath"];
			
			object.representedNodeIdentifier = subNode.identifier;
			object.location = (id)path;
			object.name = subNode.name;
			object.parser = self;
			object.index = index++;
			
			object.imageLocation = [self imageLocationForObject:keyPhotoDict];
			object.imageRepresentationType = [self requestedImageRepresentationType];
			object.imageRepresentation = nil;
		}
		[pool drain];
	}	
	inNode.subNodes = subNodes;
	inNode.objects = objects;
	[objects release];
}


//----------------------------------------------------------------------------------------------------------------------


- (void) populateAlbumNode:(IMBNode*)inNode images:(NSDictionary*)inImages
{
	// Create the objects array on demand  - even if turns out to be empty after exiting this method, because
	// without creating an array we would cause an endless loop...
	
	NSMutableArray* objects = [[NSMutableArray alloc] initWithArray:inNode.objects];
	
	// Populate the node with IMBVisualObjects for each image in the album
	
	NSUInteger index = 0;
	Class objectClass = [self objectClass];
	
	// We saved a reference to the album dictionary when this node was created
	// (ivar 'attributes') and now happily reuse it to save an outer loop (over album list) here.
	
	NSDictionary* albumDict = inNode.attributes;	
	NSArray* imageKeys = [albumDict objectForKey:@"KeyList"];
	
	for (NSString* key in imageKeys)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		NSDictionary* imageDict = [inImages objectForKey:key];
		
		if ([self shouldUseObject:imageDict])
		{
			NSString* path = [imageDict objectForKey:@"ImagePath"];
			NSString* name = [imageDict objectForKey:@"Caption"];
			if ([name isEqualToString:@""])
			{
				name = [[path lastPathComponent] stringByDeletingPathExtension];	// fallback to filename
			}
			
			IMBObject* object = [[objectClass alloc] init];
			[objects addObject:object];
			[object release];
			
			object.location = (id)path;
			object.name = name;
			object.preliminaryMetadata = imageDict;	// This metadata from the XML file is available immediately
			object.metadata = nil;					// Build lazily when needed (takes longer)
			object.metadataDescription = nil;		// Build lazily when needed (takes longer)
			object.parser = self;
			object.index = index++;
			
			object.imageLocation = [self imageLocationForObject:imageDict];
			object.imageRepresentationType = [self requestedImageRepresentationType];
			object.imageRepresentation = nil;
		}
		
		[pool drain];
	}
	
    inNode.objects = objects;
    [objects release];
}


//----------------------------------------------------------------------------------------------------------------------


@end
