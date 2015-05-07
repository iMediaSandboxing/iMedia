//
//  IMBAppleMediaLibraryPropertySynchronizer.m
//  iMedia
//
//  Created by Jörg Jacobsen on 13.02.15.
//
//

#import "IMBAppleMediaLibraryPropertySynchronizer.h"

@interface IMBAppleMediaLibraryPropertySynchronizer ()

@property (nonatomic, strong) id observedObject;
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) id valueForKey;
@property (nonatomic) dispatch_semaphore_t semaphore;

@end

@implementation IMBAppleMediaLibraryPropertySynchronizer

@synthesize observedObject=_observedObject;
@synthesize key=_key;
@synthesize valueForKey=_valueForKey;
@synthesize semaphore=_semaphore;


#pragma mark Object Lifecycle

- (instancetype)init
{
    return [self initWithKey:nil ofObject:nil];
}

/**
 Designated Initializer.
 */
- (instancetype)initWithKey:(NSString *)key ofObject:(id)object
{
    if (object == nil) {
        return nil;
    }
    NSParameterAssert(key != nil);
    
    if (self = [super init]) {
        self.key = key;
        self.observedObject = object;
    }
    return self;
}

- (void)dealloc
{
    [self.observedObject removeObserver:self forKeyPath:self.key];
}

#pragma mark Public API

+ (NSDictionary *)mediaSourcesForMediaLibrary:(MLMediaLibrary *)mediaLibrary
{
    return [self synchronousValueForObservableKey:@"mediaSources" ofObject:mediaLibrary];
}

+ (MLMediaGroup *)rootMediaGroupForMediaSource:(MLMediaSource *)mediaSource
{
    return [self synchronousValueForObservableKey:@"rootMediaGroup" ofObject:mediaSource];
}

+ (NSArray *)mediaObjectsForMediaGroup:(MLMediaGroup *)mediaGroup
{
    return [self synchronousValueForObservableKey:@"mediaObjects" ofObject:mediaGroup];
}

+ (NSImage *)iconImageForMediaGroup:(MLMediaGroup *)mediaGroup
{
    return [self synchronousValueForObservableKey:@"iconImage" ofObject:mediaGroup];
}

#pragma mark Helper

/**
 Returns value for given key of object synchronously.
 
 Must not be called from main thread for keys like "mediaSources", "rootMediaGroup", "mediaObjects"
 since it would block main thread forever!
 */
+ (id)synchronousValueForObservableKey:(NSString *)key ofObject:(id)object
{
    NSAssert(![NSThread isMainThread], @"This method must not be invoked on main thread");
    
    IMBAppleMediaLibraryPropertySynchronizer *instance = [[self alloc] initWithKey:key ofObject:object];
    
    if (instance) {
        instance.semaphore = dispatch_semaphore_create(0);
        [instance.observedObject addObserver:instance forKeyPath:instance.key options:0 context:NULL];
        instance.valueForKey = [instance.observedObject valueForKey:instance.key];
//        NSLog(@"Property value %@.%@ is %@", instance.observedObject, instance.key, instance.valueForKey);
        
        if (!instance.valueForKey) {
            // Value not present yet, will be provided asynchronously through KVO. Wait for it.
            dispatch_semaphore_wait(instance.semaphore, DISPATCH_TIME_FOREVER);
        }

#if !OS_OBJECT_USE_OBJC
		// For targets requiring 10.8 or greater we don't need (and in fact can't use) dispatch_release,
		// because it's handled automatically by ARC.
		dispatch_release(instance.semaphore);
#endif

        return instance.valueForKey;
    }
    return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == NULL) {
//        self.valueForKey = change[NSKeyValueChangeNewKey];
        self.valueForKey = [object valueForKey:keyPath];
//        NSLog(@"Property value %@.%@ is %@", self.observedObject, self.key, self.valueForKey);
        dispatch_semaphore_signal(self.semaphore);
    }
}
@end
