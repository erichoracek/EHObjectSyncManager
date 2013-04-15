//
//  EHObjectSyncManager.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/2/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHObjectSyncManager.h"

NSString * const EHObjectSyncRequestMethod = @"EHObjectSyncRequestMethod";
NSString * const EHObjectSyncClassName = @"EHObjectSyncClassName";
NSString * const EHObjectSyncDate = @"EHObjectSyncDate";
NSString * const EHObjectSyncPath = @"EHObjectSyncPath";
NSString * const EHObjectSyncRank = @"EHObjectSyncRank";
NSString * const EHUserDefaultsObjectSyncStore = @"EHUserDefaultsObjectSyncStore";

/**
 Returns the first `EHSyncDescriptor` object from the given array that matches the given object.
 
 @param syncDescriptors An array of `EHSyncDescriptor` objects.
 @param object The object to find a matching sync descriptor for.
 @return An `EHSyncDescriptor` object matching the given object, or `nil` if none could be found.
 */
static EHSyncDescriptor *EHSyncDescriptorFromArrayMatchingObject(NSArray *syncDescriptors, id object)
{
    Class searchClass = [object class];
    do {
        for (EHSyncDescriptor *syncDescriptor in syncDescriptors) {
            if ([syncDescriptor.entityMapping.objectClass isEqual:searchClass]) return syncDescriptor;
        }
        searchClass = [searchClass superclass];
    } while (searchClass);
    
    return nil;
}

@interface EHObjectSyncManager ()

@property (nonatomic, strong) NSMutableArray *mutableSyncDescriptors;
@property (nonatomic, strong) NSOperationQueue *objectSyncOperationQueue;

- (void)handlePersistentStoreManagedObjectContextDidSaveNotification:(NSNotification *)notification;
- (void)handleManagedObjectContextDidChangeNotification:(NSNotification *)notification;

- (void)sync;
- (NSString *)logStringForObjectSyncDictionary:(NSDictionary *)dictionary objectID:(NSString *)objectID;

@end

@implementation EHObjectSyncManager

- (id)initWithHTTPClient:(AFHTTPClient *)client
{
    self = [super initWithHTTPClient:client];
    if (self) {
        self.mutableSyncDescriptors = [NSMutableArray new];
        self.objectSyncOperationQueue = [NSOperationQueue new];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureSyncManagerWithManagedObjectStore:(RKManagedObjectStore *)managedObjectStore
{
#warning FIGURE OUT WHY THIS CAUSES SAVE NOTIFICATIONS TO HAVE ALL DELETED OBJECTS EVER
//    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
//    self.managedObjectContext.parentContext = managedObjectStore.persistentStoreManagedObjectContext;
//    self.managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    
    self.managedObjectContext = managedObjectStore.persistentStoreManagedObjectContext;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleManagedObjectContextDidChangeNotification:) name:NSManagedObjectContextObjectsDidChangeNotification object:self.managedObjectContext];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePersistentStoreManagedObjectContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext.parentContext];
    
    __weak typeof (self) weakSelf = self;
    [self.HTTPClient setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        if ((status == AFNetworkReachabilityStatusReachableViaWiFi) || (status == AFNetworkReachabilityStatusReachableViaWWAN)) {
            [weakSelf.managedObjectContext performBlock:^{
                [weakSelf sync];
            }];
        }
    }];
}

#pragma mark - EHObjectSyncManager

#pragma mark Sync Descriptors

- (NSArray *)syncDescriptors
{
    return [NSArray arrayWithArray:self.mutableSyncDescriptors];
}

- (void)addSyncDescriptor:(EHSyncDescriptor *)syncDescriptor
{
    NSParameterAssert(syncDescriptor);
    if ([self.syncDescriptors containsObject:syncDescriptor]) return;
    NSAssert([syncDescriptor isKindOfClass:[EHSyncDescriptor class]], @"Expected an object of type EHSyncDescriptor, got '%@'", [syncDescriptor class]);
    [self.syncDescriptors enumerateObjectsUsingBlock:^(EHSyncDescriptor *registeredDescriptor, NSUInteger idx, BOOL *stop) {
        NSAssert(![[registeredDescriptor.entityMapping objectClass] isEqual:[syncDescriptor.entityMapping objectClass]], @"Cannot add a sync descriptor for the same object class as an existing sync descriptor.");
    }];
    [self.mutableSyncDescriptors addObject:syncDescriptor];
}

- (void)addSyncDescriptorsFromArray:(NSArray *)syncDescriptors
{
    for (EHSyncDescriptor *syncDescriptor in syncDescriptors) {
        [self addSyncDescriptor:syncDescriptor];
    }
}

- (void)removeSyncDescriptor:(EHSyncDescriptor *)syncDescriptor
{
    NSParameterAssert(syncDescriptor);
    NSAssert([syncDescriptor isKindOfClass:[EHSyncDescriptor class]], @"Expected an object of type EHSyncDescriptor, got '%@'", [syncDescriptor class]);
    [self.mutableSyncDescriptors removeObject:syncDescriptor];
}

- (void)handlePersistentStoreManagedObjectContextDidSaveNotification:(NSNotification *)notification
{
    NSAssert([notification object] == self.managedObjectContext.parentContext, @"Received Managed Object Context Did Save Notification for Unexpected Context: %@", [notification object]);
    [self.managedObjectContext performBlock:^{
        [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

#pragma mark Managed Object Context Save Notification

- (void)handleManagedObjectContextDidChangeNotification:(NSNotification *)notification
{
    NSAssert([notification object] == self.managedObjectContext, @"Received Managed Object Context Did Save Notification for Unexpected Context: %@", [notification object]);
    
    NSSet *deletedObjects = notification.userInfo[NSDeletedObjectsKey];
    NSSet *updatedObjects = notification.userInfo[NSUpdatedObjectsKey];
    NSSet *insertedObjects = notification.userInfo[NSInsertedObjectsKey];
    
    if ((updatedObjects.count == 0) && (insertedObjects.count == 0) && (deletedObjects.count == 0)) {
        RKLogCritical(@"No changes, returning");
        return;
    } else {
        if (insertedObjects.count) NSLog(@"Inserted Objects %@", [insertedObjects valueForKey:@"objectID"]);
        if (updatedObjects.count) NSLog(@"Updated Objects %@", [updatedObjects valueForKey:@"objectID"]);
        if (deletedObjects.count) NSLog(@"Deleted Objects %@", [deletedObjects valueForKey:@"objectID"]);
    }
    
    // Instantiate the synchronization dictionary
    NSMutableDictionary *objectSyncStoreDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore] mutableCopy];
    if (objectSyncStoreDictionary == nil) {
        objectSyncStoreDictionary = [NSMutableDictionary dictionary];
    }
    
    // Updated Objects
    for (NSManagedObject *managedObject in updatedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingObject(self.mutableSyncDescriptors, managedObject);
        if (!syncDescriptor) continue;
        
        // Don't continue If the object doesn't exist remotely
        if ([syncDescriptor existsRemotelyBlock](managedObject) == NO) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        
        // Don't override a existing enqueued POST
        RKRequestMethod requestMethod = [objectSyncStoreDictionary[objectID][EHObjectSyncRequestMethod] integerValue];
        if (requestMethod == RKRequestMethodPOST) continue;
        
        NSDictionary *objectDictionary = @{
                                           EHObjectSyncRequestMethod : @(RKRequestMethodPUT),
                                           EHObjectSyncClassName : NSStringFromClass(managedObject.class),
                                           EHObjectSyncRank : syncDescriptor.syncRank,
                                           EHObjectSyncDate : NSDate.date
                                           };
        
        NSLog(@"OBJECT SYNC: Object Updated: %@", [self logStringForObjectSyncDictionary:objectDictionary objectID:objectID]);
        [objectSyncStoreDictionary setObject:objectDictionary forKey:objectID];
    }
    
    // Inserted Objects
    for (NSManagedObject *managedObject in insertedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingObject(self.mutableSyncDescriptors, managedObject);
        if (!syncDescriptor) continue;
        
        // If the object already exists remotely, don't enqueue a POST
        if ([syncDescriptor existsRemotelyBlock](managedObject)) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        NSDictionary *objectDictionary = @{
                                           EHObjectSyncRequestMethod : @(RKRequestMethodPOST),
                                           EHObjectSyncClassName : NSStringFromClass(managedObject.class),
                                           EHObjectSyncRank : syncDescriptor.syncRank,
                                           EHObjectSyncDate : NSDate.date
                                           };
        NSLog(@"OBJECT SYNC: Object Inserted: %@", [self logStringForObjectSyncDictionary:objectDictionary objectID:objectID]);
        [objectSyncStoreDictionary setObject:objectDictionary forKey:objectID];
    }
    
    // Deleted Objects
    for (NSManagedObject *managedObject in deletedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingObject(self.mutableSyncDescriptors, managedObject);
        if (!syncDescriptor) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        
        // If we have a non-remote object that's been deleted, just remove it from the dictionary
        if (objectSyncStoreDictionary[objectID] && [objectSyncStoreDictionary[objectID][EHObjectSyncRequestMethod] integerValue] != RKRequestMethodDELETE) {
            NSLog(@"OBJECT SYNC: Object has since deleted locally, removing from sync store dictionary: %@", managedObject);
            [objectSyncStoreDictionary removeObjectForKey:objectID];
        }
        
        // Don't continue If the object doesn't exist remotely
        if ([syncDescriptor existsRemotelyBlock](managedObject) == NO) continue;
        
        RKRoute *route = [self.router.routeSet routeForObject:managedObject method:RKRequestMethodDELETE];
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:route.pathPattern];
        NSString *path = [pathMatcher pathFromObject:managedObject addingEscapes:route.shouldEscapePath interpolatedParameters:nil];
        
        NSDictionary *objectDictionary = @{
                                           EHObjectSyncRequestMethod : @(RKRequestMethodDELETE),
                                           EHObjectSyncClassName : NSStringFromClass(managedObject.class),
                                           EHObjectSyncRank : syncDescriptor.syncRank,
                                           EHObjectSyncDate : [NSDate date],
                                           EHObjectSyncPath : path
                                           };
        NSLog(@"OBJECT SYNC: Object Deleted: %@", [self logStringForObjectSyncDictionary:objectDictionary objectID:objectID]);
        [objectSyncStoreDictionary setObject:objectDictionary forKey:objectID];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:objectSyncStoreDictionary forKey:EHUserDefaultsObjectSyncStore];
    
    [self.managedObjectContext performBlock:^{
        [self sync];
    }];
}

- (void)sync
{
    if ([self.objectSyncOperationQueue operationCount]) {
        NSLog(@"Awaiting execution of %ld enqueued connection operations: %@", (long) [self.objectSyncOperationQueue operationCount], [self.objectSyncOperationQueue operations]);
//        [self.objectSyncOperationQueue waitUntilAllOperationsAreFinished];
        return;
    }
    
    // If the object sync store is empty, no sync is needed
    NSDictionary *objectSyncDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore];
    if (objectSyncDictionary == nil || objectSyncDictionary.count == 0) {
        return;
    }
    
    // Establish a sync rank dictionation with each of the operations for that rank (keyed by rank)
    NSMutableDictionary *operationsForSyncRank = [NSMutableDictionary new];
    self.objectSyncOperationQueue.suspended = YES;
    
    [objectSyncDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *objectIDStringURI, NSDictionary *objectDictionary, BOOL *stop) {
        
        NSLog(@"OBJECT SYNC: Building Sync Operation: %@", [self logStringForObjectSyncDictionary:objectDictionary objectID:objectIDStringURI]);
        
        // Add an array for this rank if it doesn't exist
        NSMutableArray *syncRankOperations = operationsForSyncRank[objectDictionary[EHObjectSyncRank]];
        if (!syncRankOperations) {
            syncRankOperations = [NSMutableArray new];
            operationsForSyncRank[objectDictionary[EHObjectSyncRank]] = syncRankOperations;
        }
        
        EHObjectSyncOperation *objectSyncOperation = [EHObjectSyncOperation new];
        objectSyncOperation.objectIDStringURI = objectIDStringURI;
        objectSyncOperation.syncClass = NSClassFromString(objectDictionary[EHObjectSyncClassName]);
        objectSyncOperation.syncDate = objectDictionary[EHObjectSyncDate];
        objectSyncOperation.syncRank = objectDictionary[EHObjectSyncRank];
        objectSyncOperation.syncRequestMethod = objectDictionary[EHObjectSyncRequestMethod];
        
        switch ([objectDictionary[EHObjectSyncRequestMethod] integerValue]) {
            case RKRequestMethodPOST:
            case RKRequestMethodPUT: {
                NSManagedObjectID *managedObjectID = [[self.managedObjectContext persistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:objectIDStringURI]];
                NSError *error;
                NSManagedObject *syncObject = [self.managedObjectContext existingObjectWithID:managedObjectID error:&error];
                // If we're unable to find object in our MOC, remove it from sync dictionary, and don't enqueue the request
                if (!syncObject) {
                    NSMutableDictionary *synchronizationDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore] mutableCopy];
                    NSLog(@"Removing orphaned object %@, error %@", objectIDStringURI, [error debugDescription]);
                    [synchronizationDictionary removeObjectForKey:objectIDStringURI];
                    [[NSUserDefaults standardUserDefaults] setObject:synchronizationDictionary forKey:EHUserDefaultsObjectSyncStore];
                    return;
                }
                objectSyncOperation.syncObject = syncObject;
                break;
            }
            case RKRequestMethodDELETE:
                objectSyncOperation.syncPath = objectDictionary[EHObjectSyncPath];
                break;
            default:
                NSAssert(NO, @"Unsupported request method");
                return;
                break;
        }
        
        [self.objectSyncOperationQueue addOperation:objectSyncOperation];
        [syncRankOperations addObject:objectSyncOperation];
    }];
    
    NSArray *sortedRanks = [[operationsForSyncRank allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *rank1, NSNumber *rank2) {
        return [rank1 compare:rank2];
    }];
    NSNumber *highRank = nil;
    for (NSNumber *lowRank in sortedRanks) {
        if (highRank) {
            NSLog(@"Setting all rank %@ requests to depend on rank %@ requests", lowRank, highRank);
            for (NSOperation *lowRankOperation in operationsForSyncRank[lowRank]) {
                for (NSOperation *highRankOperation in operationsForSyncRank[highRank]) {
                    [lowRankOperation addDependency:highRankOperation];
                }
            }
        }
        highRank = lowRank;
    }
    
    self.objectSyncOperationQueue.suspended = NO;
}

- (NSString *)logStringForObjectSyncDictionary:(NSDictionary *)dictionary objectID:(NSString *)objectID
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
    });
    NSString *formattedDate = [dateFormatter stringFromDate:dictionary[EHObjectSyncDate]];
    
    return [NSString stringWithFormat:@"%@ (ObjectID: %@, Rank %@, Date %@)", dictionary[EHObjectSyncClassName], objectID, dictionary[EHObjectSyncRank], formattedDate];
}

@end

@interface EHSyncDescriptor ()

@property (nonatomic, strong, readwrite) RKEntityMapping *entityMapping;
@property (nonatomic, copy, readwrite) NSNumber *syncRank;
@property (nonatomic, strong, readwrite) Class objectClass;
@property (nonatomic, strong, readwrite) EHSyncDescriptorExistsRemotelyBlock existsRemotelyBlock;

@end

@implementation EHSyncDescriptor

+ (instancetype)syncDescriptorWithMapping:(RKEntityMapping *)mapping
                                 syncRank:(NSNumber *)syncRank
                      existsRemotelyBlock:(EHSyncDescriptorExistsRemotelyBlock)existsRemotelyBlock;
{
    NSParameterAssert(mapping);
    NSParameterAssert(syncRank);
    NSParameterAssert(existsRemotelyBlock);
    
    EHSyncDescriptor *syncDescriptor = [self new];
    syncDescriptor.entityMapping = mapping;
    syncDescriptor.syncRank = syncRank;
    syncDescriptor.existsRemotelyBlock = existsRemotelyBlock;
    return syncDescriptor;
}

@end

@interface EHObjectSyncOperation()

@property (nonatomic, assign) BOOL finishedCleanUp;
@property (nonatomic, strong, readwrite) NSOperation *syncRequestOperation;

@end

@implementation EHObjectSyncOperation

#pragma mark - NSOperation

- (void)start
{
    // Ready -> Executing
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isReady"];
    [self didChangeValueForKey:@"isReady"];
    [self didChangeValueForKey:@"isExecuting"];
    
    [self startRequest];
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isFinished
{
    return ([self.syncRequestOperation isFinished] && self.finishedCleanUp);
}

- (BOOL)isExecuting
{
    return ([self.syncRequestOperation isExecuting] || !self.finishedCleanUp);
}

#pragma mark - EHObjectSyncOperation

- (void)startRequest
{
    switch (self.syncRequestMethod.integerValue) {
        case RKRequestMethodPOST:
        case RKRequestMethodPUT:
            NSAssert(self.syncObject, @"A POST and PUT object sync request requres a sync object");
            break;
        case RKRequestMethodDELETE:
            NSAssert(self.syncPath, @"A DELETE object sync request requres a sync path");
            break;
    }
    
    switch (self.syncRequestMethod.integerValue) {
        case RKRequestMethodPOST: {
            NSLog(@"Enqueueing POST (%@)", self.syncClass);
            RKObjectRequestOperation *POSTRequestOperation = [[EHObjectSyncManager sharedManager] appropriateObjectRequestOperationWithObject:self.syncObject method:RKRequestMethodPOST path:nil parameters:nil];
            [POSTRequestOperation setCompletionBlockWithSuccess:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
                NSLog(@"POST Succeeded (%@)", self.syncClass);
                [self cleanupRequest];
            } failure:^(RKObjectRequestOperation *operation, NSError *error) {
                NSLog(@"POST Failure (%@): %@", self.syncClass, error);
                [self cleanupRequest];
            }];
            self.syncRequestOperation = POSTRequestOperation;
            [[EHObjectSyncManager sharedManager].operationQueue addOperation:POSTRequestOperation];
            break;
        }
        case RKRequestMethodPUT: {
            NSLog(@"Enqueueing PUT (%@)", self.syncClass);
            RKObjectRequestOperation *PUTRequestOperation = [[EHObjectSyncManager sharedManager] appropriateObjectRequestOperationWithObject:self.syncObject method:RKRequestMethodPUT path:nil parameters:nil];
            [PUTRequestOperation setCompletionBlockWithSuccess:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
                NSLog(@"PUT Succeeded (%@)", self.syncClass);
                [self cleanupRequest];
            } failure:^(RKObjectRequestOperation *operation, NSError *error) {
                NSLog(@"PUT Failure (%@): %@", self.syncClass, error);
                [self cleanupRequest];
            }];
            self.syncRequestOperation = PUTRequestOperation;
            [[EHObjectSyncManager sharedManager].operationQueue addOperation:PUTRequestOperation];
            break;
        }
        case RKRequestMethodDELETE: {
            NSLog(@"Enqueueing DELETE (%@)", self.syncClass);
            NSURLRequest *deleteRequest = [(AFHTTPClient *)[EHObjectSyncManager sharedManager] requestWithMethod:@"DELETE" path:self.syncPath parameters:nil];
            AFJSONRequestOperation *DELETERequestOperation = [AFJSONRequestOperation JSONRequestOperationWithRequest:deleteRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                NSLog(@"DELETE Succeeded (%@)", self.syncClass);
                [self cleanupRequest];
            } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                NSLog(@"DELETE Failure (%@): %@", self.syncClass, error);
                [self cleanupRequest];
            }];
            self.syncRequestOperation = DELETERequestOperation;
            [[EHObjectSyncManager sharedManager].operationQueue addOperation:DELETERequestOperation];
            break;
        }
        default:
            NSAssert(NO, @"Unsupported request method");
            break;
    }
}

- (void)cleanupRequest;
{
    NSAssert([self.syncRequestOperation isFinished], @"Request operation must be finished");
    
    if ([self.syncRequestOperation isKindOfClass:RKObjectRequestOperation.class]) {
        RKObjectRequestOperation *requestOperation = (RKObjectRequestOperation *)self.syncRequestOperation;
        if (!requestOperation.error) {
            [self removeObjectFromSyncDictionary];
        }
        if (requestOperation.HTTPRequestOperation.response.statusCode == 404) {
            [self removeObjectFromSyncDictionary];
        }
    }
    else if ([self.syncRequestOperation isKindOfClass:AFJSONRequestOperation.class]) {
        AFHTTPRequestOperation *requestOperation = (AFHTTPRequestOperation *)self.syncRequestOperation;
        if (!requestOperation.error) {
            [self removeObjectFromSyncDictionary];
        }
        if (requestOperation.response.statusCode == 404) {
            [self removeObjectFromSyncDictionary];
        }
    }

    // Executing -> Finished
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    self.finishedCleanUp = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)removeObjectFromSyncDictionary
{
    NSMutableDictionary *synchronizationDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore] mutableCopy];
    NSLog(@"Removing URI %@", self.objectIDStringURI);
    [synchronizationDictionary removeObjectForKey:self.objectIDStringURI];
    [[NSUserDefaults standardUserDefaults] setObject:synchronizationDictionary forKey:EHUserDefaultsObjectSyncStore];
}

@end
