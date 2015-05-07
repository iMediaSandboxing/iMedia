//
//  IMBAppleMediaLibraryParser.m
//  iMedia
//
//  Created by Jörg Jacobsen on 24.02.15.
//
//

#import "NSObject+iMedia.h"
#import "NSWorkspace+iMedia.h"
#import "NSURL+iMedia.h"
#import "IMBConfig.h"
#import "IMBNodeObject.h"
#import "IMBAppleMediaLibraryParser.h"
#import "IMBAppleMediaLibraryPropertySynchronizer.h"

#define USE_PARSER_ANNOTATED_LIBRARY_NAME 0

#define CREATE_MEDIA_OBJECTS_CONCURRENTLY 1

#define MEASURE_EXECUTION_TIME 0

#if MEASURE_EXECUTION_TIME
    #define START_MEASURE(id) NSDate *start ## id = [NSDate date]
    #define STOP_MEASURE(id)  NSDate *stop ## id  = [NSDate date]
    #define LOG_MEASURED_TIME(id, ...) NSLog(@"Took %f secs to execute %@", [stop ## id timeIntervalSinceDate:start ## id], [NSString stringWithFormat: __VA_ARGS__])
#else
    #define START_MEASURE(id)
    #define STOP_MEASURE(id)
    #define LOG_MEASURED_TIME(id, ...)
#endif

@implementation IMBAppleMediaLibraryParser

@synthesize AppleMediaLibrary = _AppleMediaLibrary;
@synthesize AppleMediaSource = _AppleMediaSource;
@synthesize configuration = _configuration;

#pragma mark - Configuration

- (NSString *)identifier
{
    return [self.configuration mediaSourceIdentifier];
}

+ (MLMediaType)MLMediaTypeForIMBMediaType:(NSString *)mediaType
{
    if ([mediaType isEqualToString:kIMBMediaTypeImage]) {
        return MLMediaTypeImage;
    } else if ([mediaType isEqualToString:kIMBMediaTypeMovie]){
        return MLMediaTypeMovie;
    } else if ([mediaType isEqualToString:kIMBMediaTypeAudio]){
        return MLMediaTypeAudio;
    }
    return 0;
}

- (NSString *)mediaType
{
    switch ([self.configuration mediaType]) {
        case MLMediaTypeImage:
            return kIMBMediaTypeImage;
            break;
            
        case MLMediaTypeMovie:
            return kIMBMediaTypeMovie;
            break;
            
        case MLMediaTypeAudio:
            return kIMBMediaTypeAudio;
            break;
            
        default:
            return kIMBMediaTypeImage;
    }
}

/**
 */
- (instancetype)initializeMediaLibrary
{
    NSDictionary *libraryOptions = @{MLMediaLoadIncludeSourcesKey : [NSArray arrayWithObject:[self.configuration mediaSourceIdentifier]]};
    self.AppleMediaLibrary = [[MLMediaLibrary alloc] initWithOptions:libraryOptions];
    NSDictionary *mediaSources = [IMBAppleMediaLibraryPropertySynchronizer mediaSourcesForMediaLibrary:self.AppleMediaLibrary];
    self.AppleMediaSource = mediaSources[[self.configuration mediaSourceIdentifier]];
    
    return self;
}

#pragma mark - Mandatory overrides from superclass

/**
 */
- (IMBNode *)unpopulatedTopLevelNode:(NSError **)outError
{
    START_MEASURE(1);
    NSError *error = nil;
    
    // (Re-)instantiate media library and media source (in Apple speak), because content might have changed on disk. Note though that this yet doesn't seem to have an effect when media library changes (Apple doesn't seem to update its object cache).
    [self initializeMediaLibrary];
    
    MLMediaGroup *rootMediaGroup = [IMBAppleMediaLibraryPropertySynchronizer rootMediaGroupForMediaSource:self.AppleMediaSource];
    
    // Is there a matching media source?
    
    if (!rootMediaGroup) return nil;

    // Assign media source URL as late as possible since some media sources only provide it through attributes dictionary of root media group (e.g. iPhoto)
//    self.mediaSource = [self mediaSourceURLForGroup:rootMediaGroup];
    
    //  create an empty root node (unpopulated and without subnodes)
    
    IMBNode *node = [[IMBNode alloc] initWithParser:self topLevel:YES];
    node.name = [self libraryName];
    node.groupType = kIMBGroupTypeLibrary;
    node.icon = [[NSWorkspace imb_threadSafeWorkspace] iconForFile:[self appPath]];
    node.isIncludedInPopup = YES;
    node.isLeafNode = NO;
    node.mediaSource = self.mediaSource;
    node.accessibility = self.mediaSource ? [self mediaSourceAccessibility] : kIMBResourceIsAccessible;
    node.isAccessRevocable = NO;
    node.identifier = [self globalIdentifierForMediaGroup:rootMediaGroup];
    
    if ([self mediaSourceAccessibility] == kIMBResourceIsAccessible) {
        node.watchedPath = [self.mediaSource path];
    }
    if (outError) {
        *outError = error;
    }
    STOP_MEASURE(1);
    LOG_MEASURED_TIME(1, @"Create unpopulated top-level node %@", [self.configuration mediaSourceIdentifier]);
    return node;
}

/**
 */
- (BOOL) populateNode:(IMBNode *)inParentNode error:(NSError **)outError
{
    NSError *error = nil;
    MLMediaGroup *parentGroup = [self mediaGroupForNode:inParentNode];
    NSArray *childGroups = [parentGroup childGroups];

    // Create the objects array on demand  - even if turns out to be empty after exiting this method, because without creating an array we would cause an endless loop...
    
    NSMutableArray* objects = [NSMutableArray array];
    
    if (!inParentNode.objects && ([childGroups count] == 0 || ![self.configuration shouldPopulateNodesWithNodeObjects]))
    {
        START_MEASURE(1);
        NSArray *mediaObjects = [IMBAppleMediaLibraryPropertySynchronizer mediaObjectsForMediaGroup:parentGroup];
        STOP_MEASURE(1);
        LOG_MEASURED_TIME(1, @"fetch of media Objects for group %@", parentGroup.name);
        
#if CREATE_MEDIA_OBJECTS_CONCURRENTLY
        dispatch_group_t dispatchGroup = dispatch_group_create();
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(8);
#endif
        
        START_MEASURE(2);
        
        for (MLMediaObject *mediaObject in mediaObjects)
        {
#if CREATE_MEDIA_OBJECTS_CONCURRENTLY
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            dispatch_group_async(dispatchGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
#endif
                if ([self shouldUseMediaObject:mediaObject])
                {
                    
                    IMBObject *object = [self objectForMediaObject:mediaObject];
                    
                    @synchronized(objects) {
                        [objects addObject:object];
                    }
                }
#if CREATE_MEDIA_OBJECTS_CONCURRENTLY
                dispatch_semaphore_signal(semaphore);
            });
#endif
        }
#if CREATE_MEDIA_OBJECTS_CONCURRENTLY
        dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
#if !OS_OBJECT_USE_OBJC
	// Only required for 10.7 deployment targets and earlier
	dispatch_release(dispatchGroup);
	dispatch_release(semaphore);
#endif
#endif
        STOP_MEASURE(2);
        LOG_MEASURED_TIME(2, @"IMBObjects creation for group %@", parentGroup.name);
    }
    
    NSMutableArray* subnodes = [inParentNode mutableArrayForPopulatingSubnodes];
    
    NSLog(@"Group %@ has %zd child groups", parentGroup.name, [childGroups count]);
    
    START_MEASURE(3);
    
    for (MLMediaGroup *mediaGroup in childGroups) {
        
        if ([self shouldUseMediaGroup:mediaGroup]) {
            // Create node for this album...
            
            IMBNode *childNode = [self nodeForMediaGroup:mediaGroup parentNode:inParentNode];
            
            // Optimization for subnodes that share the same media objects with their parent node
            
            if ([self shouldReuseMediaObjectsOfParentGroupForGroup:mediaGroup]) {
                childNode.objects = inParentNode.objects;
                [self populateNode:childNode error:&error];
            }
            
            // Add the new album node to its parent (inRootNode)...
            
            [subnodes addObject:childNode];
            
            if ([childGroups count] > 0 && [self.configuration shouldPopulateNodesWithNodeObjects]) {
                [objects addObject:[self nodeObjectForNode:childNode]];
            }
            
//            NSLog(@"Initializing subgroup: %@ (%@)", [mediaGroup name], [mediaGroup identifier]);
            
        }
    }
    if (!inParentNode.objects) inParentNode.objects = objects;

    STOP_MEASURE(3);
    LOG_MEASURED_TIME(3, @"subnodes creation for group %@", parentGroup.name);
    
    if (*outError) *outError = error;
    return YES;
}


//
//
- (id)thumbnailForObject:(IMBObject *)inObject error:(NSError **)outError
{
    NSError *error = nil;
    
    // IKImageBrowser can also deal with NSData type (IKImageBrowserNSDataRepresentationType)
    
    NSURL *url = nil;
    if (inObject.imageLocation)
    {
        url = [self URLForBookmark:(NSData *)inObject.imageLocation error:&error];
    } else {
        MLMediaObject *mediaObject = [self mediaObjectForObject:inObject];
        url = mediaObject.thumbnailURL;
    }
    
    if (url) {
        id thumbnail = nil;
        
        [url startAccessingSecurityScopedResource];
        
        if ([inObject.imageRepresentationType isEqualToString:IKImageBrowserNSImageRepresentationType]) {
            thumbnail = (id)[[NSImage alloc] initWithContentsOfURL:url];
        }
        else if ([inObject.imageRepresentationType isEqualToString:IKImageBrowserCGImageRepresentationType])
        {
            thumbnail = (id)[self thumbnailFromLocalImageFileForObject:inObject error:outError];
        }
        else
        {
            inObject.imageRepresentationType = IKImageBrowserNSDataRepresentationType;
            thumbnail = (id)[NSData dataWithContentsOfURL:url];
        }
        [url stopAccessingSecurityScopedResource];
        
        return thumbnail;
    } else {
        inObject.imageRepresentationType = IKImageBrowserCGImageRepresentationType;
        return (id)[self thumbnailFromLocalImageFileForObject:inObject error:outError];
    }
    return nil;
}

- (NSDictionary *)metadataForObject:(IMBObject *)inObject error:(NSError *__autoreleasing *)outError
{
    NSError *error = nil;
    NSDictionary *metadata = nil;
    if ([self.configuration respondsToSelector:@selector(metadataForObject:error:)])
    {
        metadata = [self.configuration metadataForObject:inObject error:&error];
    } else {
        metadata = @{};
    }
    if (outError) *outError = error;

    return metadata;
}

/**
 */
- (NSData*) bookmarkForObject:(IMBObject*)inObject error:(NSError**)outError
{
    NSError* error = nil;
    
    MLMediaObject *mediaObject = [self mediaObjectForObject:inObject];
    return[self bookmarkForURL:mediaObject.URL error:&error];
}

#pragma mark - Media Group

/**
 Converts an MLMediaLibrary group into iMedia's "native" IMBNode.
 */
- (IMBNode *)nodeForMediaGroup:(MLMediaGroup *)mediaGroup parentNode:(IMBNode *)parentNode
{
    IMBNode* node = [[IMBNode alloc] initWithParser:self topLevel:NO];
    
    node.isLeafNode = [[mediaGroup childGroups] count] == 0;
    node.icon = [IMBAppleMediaLibraryPropertySynchronizer iconImageForMediaGroup:mediaGroup];
// albumNode.highlightIcon = ...;
    node.name = [self localizedNameForMediaGroup:mediaGroup];
    node.watchedPath = parentNode.watchedPath;	// These two lines are important to make file watching work for nested
    node.watcherType = kIMBWatcherTypeNone;     // subfolders. See IMBLibraryController _reloadNodesWithWatchedPath:
    
    node.identifier = [self globalIdentifierForMediaGroup:mediaGroup];
    
    return node;
}

/**
 */
- (MLMediaGroup *)mediaGroupForNode:(IMBNode *)node
{
    NSString *mediaGroupIdentifier = [node.identifier substringFromIndex:[[self identifierPrefix] length]];
    return [self.AppleMediaSource mediaGroupForIdentifier:mediaGroupIdentifier];
}

/**
 */
- (IMBNodeObject *)nodeObjectForNode:(IMBNode *)node
{
    IMBNodeObject* object = [[IMBNodeObject alloc] init];
    object.identifier = node.identifier;
    object.representedNodeIdentifier = node.identifier;
//    object.location = url;
    object.imageRepresentation = [IMBAppleMediaLibraryPropertySynchronizer iconImageForMediaGroup:[self mediaGroupForNode:node]];
//    object.needsImageRepresentation = NO;
    object.name = node.name;
    object.metadata = nil;
    object.parserIdentifier = self.identifier;
    
    return object;
}

/**
 Delegates the message to the receiver's parser configuration if it implements it. Otherwise returns YES.
 */
- (BOOL)shouldUseMediaGroup:(MLMediaGroup *)mediaGroup
{
    if ([self.configuration respondsToSelector:@selector(shouldUseMediaGroup:)]) {
        return [self.configuration shouldUseMediaGroup:mediaGroup];
    }
    return YES;
}

/**
 Delegates the message to the receiver's parser configuration if it implements it. Otherwise returns NO.
 */
- (BOOL)shouldReuseMediaObjectsOfParentGroupForGroup:(MLMediaGroup *)mediaGroup
{
    if ([self.configuration respondsToSelector:@selector(shouldReuseMediaObjectsOfParentGroupForGroup:)]) {
        return [self.configuration shouldReuseMediaObjectsOfParentGroupForGroup:mediaGroup];
    }
    return NO;
}

- (NSString *)globalIdentifierForMediaGroup:(MLMediaGroup *)mediaGroup
{
    NSParameterAssert(mediaGroup.identifier != nil);
    
    if (mediaGroup.identifier) {
        return [[self identifierPrefix] stringByAppendingString:mediaGroup.identifier];
    } else {
        NSLog(@"%s: media group %@ has no identifier", __FUNCTION__, mediaGroup.name);
        return [self identifierPrefix];
    }
}

/**
 Returns whether a media group was created automatically by the app that owns the media library (and not by the user).
 */
- (BOOL)nonUserCreatedGroup:(MLMediaGroup *)mediaGroup
{
    return [[self.configuration identifiersOfNonUserCreatedGroups] containsObject:mediaGroup.identifier];
}

/**
 Despite its claims that a media group's name property returns a localized name for non-user created groups it always returns an english name for Photos and iPhoto libraries (as of 2015-03-06). So, we localize ourselves.
 */
- (NSString *)localizedNameForMediaGroup:(MLMediaGroup *)mediaGroup
{
    if ([self nonUserCreatedGroup:mediaGroup]) {
        NSString *localizationKey = [NSString stringWithFormat:@"%@.%@", [self.configuration mediaSourceIdentifier], mediaGroup.identifier];
        return NSLocalizedStringWithDefaultValue(localizationKey, nil, IMBBundle(), nil, @"Localized string key must match media source identifier concatenated via dot with media group identifier");
    } else {
        return mediaGroup.name;
    }
}

#pragma mark - Media Object

/**
 Converts an MLMediaLibrary object into iMedia's "native" IMBObject.
 */
 - (IMBObject *)objectForMediaObject:(MLMediaObject *)mediaObject
{
    IMBObject *object = [[IMBObject alloc] init];
    
    object.identifier = mediaObject.identifier;
    object.parserIdentifier = [self identifier];
    object.name = [self nameForMediaObject:mediaObject];

    if ([IMBConfig clientAppCanHandleSecurityScopedBookmarks])
    {
        // In this case do not provide URL to framework because it will lose security scope anyway because of encode/decode dance
        object.accessibility = kIMBResourceIsAccessibleSecurityScoped;
    } else {
        object.location = mediaObject.URL;
        object.accessibility = [self accessibilityForObject:object];
    }
// Since the following two operations are expensive we postpone them to the point when we actually need the data
//    object.locationBookmark = [self bookmarkForURL:mediaObject.URL error:&error];
//    object.imageLocation = [self bookmarkForURL:mediaObject.thumbnailURL error:&error];
    
    object.imageRepresentationType = IKImageBrowserNSImageRepresentationType;
    object.preliminaryMetadata = mediaObject.attributes;
    
//    NSLog(@"Media object URL: %@", [object location]);
    return object;
}

/**
 Fetches the object from Apple's media library that corresponds to iMedia's "native" IMBObject.
 */
- (MLMediaObject *)mediaObjectForObject:(IMBObject *)object
{
    if ([object isKindOfClass:[IMBNodeObject class]]) {
        IMBNodeObject *nodeObject = (IMBNodeObject *)object;
        NSString *mediaGroupIdentifier = [nodeObject.representedNodeIdentifier substringFromIndex:[[self identifierPrefix] length]];
        MLMediaGroup *mediaGroup = (MLMediaGroup *)[self.AppleMediaSource mediaGroupForIdentifier:mediaGroupIdentifier];
        return [self keyMediaObjectForMediaGroup:mediaGroup];
    } else {
        return [self.AppleMediaSource mediaObjectForIdentifier:object.identifier];
    }
}

/**
 */
- (BOOL)shouldUseMediaObject:(MLMediaObject *)mediaObject
{
    return ([self.configuration mediaType] == mediaObject.mediaType);
}

/**
 */
- (NSString *)nameForMediaObject:(MLMediaObject *)mediaObject
{
    if (mediaObject.name) {
        return mediaObject.name;
    } else {
        return [[mediaObject.URL lastPathComponent] stringByDeletingPathExtension];
    }
}

/**
 */
- (MLMediaObject *)keyMediaObjectForMediaGroup:(MLMediaGroup *)mediaGroup
{
    MLMediaObject *mediaObject = nil;
    
    if ([self.configuration respondsToSelector:@selector(keyMediaObjectForMediaGroup:fromMediaSource:)]) {
        mediaObject = [self.configuration keyMediaObjectForMediaGroup:mediaGroup fromMediaSource:self.AppleMediaSource];
    }
    if (mediaObject == nil) {
        NSArray *mediaObjects = [IMBAppleMediaLibraryPropertySynchronizer mediaObjectsForMediaGroup:mediaGroup];
        mediaObject = [mediaObjects lastObject];
    }
    return mediaObject;
}

/**
 Returns whether this object is hidden in Photos app (users can hide media objects in Photos app).
 @discussion
 Do not utilize this media object's property since media objects will already be treated by MediaLibrary framework according to their hidden status in Photos app. And hidden objects are not visible in Years/Collections/Moments but visible in albums by default.
 */
- (BOOL)hiddenMediaObject:(MLMediaObject *)mediaObject
{
    return [((NSNumber *)mediaObject.attributes[@"Hidden"]) boolValue];
}

#pragma mark - Utility

/**
 Returns path to app bundle associated with.
 */
- (NSString *) appPath
{
    return [[NSWorkspace imb_threadSafeWorkspace] absolutePathForAppBundleWithIdentifier:[self.configuration sourceAppBundleIdentifier]];
}

/**
 Returns the library name of the receiver or its qualified version.
 @discussion
 Usage of qualified library name is determined via preprocessor switch USE_QUALIFIED_LIBRARY_NAME.
 */
- (NSString *)libraryName
{
    NSString *libraryName = nil;
    if ([self.configuration respondsToSelector:@selector(libraryName)]) {
        libraryName = [self.configuration libraryName];
    } else {
        libraryName = [[NSBundle bundleWithPath:[self appPath]] localizedInfoDictionary][@"CFBundleDisplayName"];
    }
#if USE_PARSER_ANNOTATED_LIBRARY_NAME
    return [NSString stringWithFormat:@"%@ (Apple Media Library)", libraryName];
#else
    return libraryName;
#endif
}

- (NSString *)identifierPrefix
{
    NSString *mediaSourcePath = [self.mediaSource path];
    return mediaSourcePath ? mediaSourcePath : [self.configuration mediaSourceIdentifier];
}

/**
 Returns a read-only app-security-scoped bookmark for URL.
 */
- (NSData *)bookmarkForURL:(NSURL *)URL error:(NSError *__autoreleasing *)outError
{
    NSError *error = nil;
    
    [URL startAccessingSecurityScopedResource];
    NSData *bookmark = [URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope|NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&error];
    [URL stopAccessingSecurityScopedResource];
    
    if (outError) *outError = error;
    return bookmark;
}

/**
 Returns an app-security-scoped URL for bookmark.
 */
- (NSURL *)URLForBookmark:(NSData *)bookmark error:(NSError *__autoreleasing *)outError
{
    NSError *error = nil;
    BOOL stale = NO;
    
    NSURL *URL =[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    
    if (outError) *outError = error;
    return URL;
}
@end
