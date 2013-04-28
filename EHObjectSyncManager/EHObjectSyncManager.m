//
//  EHObjectSyncManager.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/2/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHObjectSyncManager.h"

NSString * const EHObjectSyncRequestMethod = @"EHObjectSyncRequestMethod"; // RKRequestMethod string
NSString * const EHObjectSyncClassName     = @"EHObjectSyncClassName";     // Class name of the object that changed
NSString * const EHObjectSyncDate          = @"EHObjectSyncDate";          // Date that the change occurred
NSString * const EHObjectSyncPath          = @"EHObjectSyncPath";          // String path that the request occurs at (DELETE only)

NSString * const EHObjectSyncFileName = @"EHObjectSyncManagerPendingRequests.plist";

static EHSyncDescriptor *EHSyncDescriptorFromArrayMatchingClass(NSArray *syncDescriptors, Class searchClass)
{
    do {
        for (EHSyncDescriptor *syncDescriptor in syncDescriptors) {
            if ([syncDescriptor.entityMapping.objectClass isEqual:searchClass]) return syncDescriptor;
        }
        searchClass = [searchClass superclass];
    } while (searchClass);
    return nil;
}

static NSString *EHLogStringFromObjectIDAndSyncDictionary(NSString *objectID, NSDictionary *syncDictionary)
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
    });
    NSString *formattedDate = [dateFormatter stringFromDate:syncDictionary[EHObjectSyncDate]];
    return [NSString stringWithFormat:@"%@ %@ (ObjectID: %@, Date %@)", syncDictionary[EHObjectSyncRequestMethod], syncDictionary[EHObjectSyncClassName], objectID, formattedDate];
}

@interface EHObjectSyncManager ()

@property (nonatomic, strong) NSMutableDictionary *syncRequestDictionary;
@property (nonatomic, strong) NSMutableArray *mutableSyncDescriptors;
@property (nonatomic, strong) NSOperationQueue *objectSyncOperationQueue;

- (void)handlePersistentStoreManagedObjectContextDidSaveNotification:(NSNotification *)notification;
- (void)handleManagedObjectContextDidChangeNotification:(NSNotification *)notification;

- (void)sync;

@end

@implementation EHObjectSyncManager

#pragma mark - RKObjectManager

- (id)initWithHTTPClient:(AFHTTPClient *)client
{
    self = [super initWithHTTPClient:client];
    if (self) {
        self.mutableSyncDescriptors = [NSMutableArray new];
        self.objectSyncOperationQueue = [NSOperationQueue new];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveSyncRequestDictionaryFile) name:UIApplicationWillTerminateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveSyncRequestDictionaryFile) name:UIApplicationWillResignActiveNotification object:nil];
        
        [self loadSyncRequestDictionaryFile];
        if (!self.syncRequestDictionary) {
            self.syncRequestDictionary = [NSMutableDictionary dictionary];
        }
        [self saveSyncRequestDictionaryFile];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
}

- (void)configureSyncManagerWithManagedObjectStore:(RKManagedObjectStore *)managedObjectStore
{
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

- (void)enqueueObjectRequestOperation:(RKObjectRequestOperation *)objectRequestOperation
{
#warning ensure that requests aren't enqued that will update that state of objects
}

#pragma mark - EHObjectSyncManager

#pragma mark Sync Dictionary

+ (dispatch_queue_t)sharedQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        queue = dispatch_queue_create([NSStringFromClass(self.class) UTF8String], DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (NSURL *)syncRequestDictionaryFileURL
{
    // Place in same directory as Core Data store
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [NSURL fileURLWithPathComponents:@[ [paths lastObject], EHObjectSyncFileName ]];
}

- (void)loadSyncRequestDictionaryFile
{
    dispatch_async([self.class sharedQueue], ^{
        NSError *error;
        if ([[self syncRequestDictionaryFileURL] checkResourceIsReachableAndReturnError:&error]) {
            self.syncRequestDictionary = [[NSMutableDictionary alloc] initWithContentsOfURL:[self syncRequestDictionaryFileURL]];
        } else {
            NSLog(@"Unable to load sync request dictionary file %@", [error debugDescription]);
        }
    });
}

- (void)saveSyncRequestDictionaryFile
{
    // Create a copy on the main thread, and save it on the background thread so that it's not being mutated during saving
    NSMutableDictionary *syncRequestDictionaryToSave = [self.syncRequestDictionary copy];
    dispatch_async([self.class sharedQueue], ^{
        if (![syncRequestDictionaryToSave writeToURL:[self syncRequestDictionaryFileURL] atomically:YES]) {
            NSLog(@"Unable to write sync request dictionary file");
        }
    });
}

- (void)removeSyncDictionaryForObjectIDStringURI:(NSString *)objectIDStringURI
{
    NSParameterAssert(self.syncRequestDictionary[objectIDStringURI]);
    [self.syncRequestDictionary removeObjectForKey:objectIDStringURI];
    [self saveSyncRequestDictionaryFile];
}

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
        RKLogCritical(@"No changes");
        return;
    } else {
        if (insertedObjects.count) NSLog(@"Inserted Objects %@", [insertedObjects valueForKey:@"objectID"]);
        if (updatedObjects.count) NSLog(@"Updated Objects %@", [updatedObjects valueForKey:@"objectID"]);
        if (deletedObjects.count) NSLog(@"Deleted Objects %@", [deletedObjects valueForKey:@"objectID"]);
    }
    
    // Updated Objects
    for (NSManagedObject *managedObject in updatedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingClass(self.mutableSyncDescriptors, managedObject.class);
        if (!syncDescriptor) continue;
        
        // Don't continue If the object doesn't exist remotely
        if ([syncDescriptor existsRemotelyBlock](managedObject) == NO) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        
        // Don't override a existing enqueued POST
        RKRequestMethod requestMethod = [self.syncRequestDictionary[objectID][EHObjectSyncRequestMethod] integerValue];
        if (requestMethod == RKRequestMethodPOST) continue;
        
        NSDictionary *syncDictionary = @{
            EHObjectSyncRequestMethod : RKStringFromRequestMethod(RKRequestMethodPUT),
            EHObjectSyncClassName : NSStringFromClass(managedObject.class),
            EHObjectSyncDate : NSDate.date
        };
        
        NSLog(@"OBJECT SYNC: Object Updated: %@", EHLogStringFromObjectIDAndSyncDictionary(objectID, syncDictionary));
        [self.syncRequestDictionary setObject:syncDictionary forKey:objectID];
    }
    
    // Inserted Objects
    for (NSManagedObject *managedObject in insertedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingClass(self.mutableSyncDescriptors, managedObject.class);
        if (!syncDescriptor) continue;
        
        // If the object already exists remotely, don't enqueue a POST
        if ([syncDescriptor existsRemotelyBlock](managedObject)) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        NSDictionary *syncDictionary = @{
            EHObjectSyncRequestMethod : RKStringFromRequestMethod(RKRequestMethodPOST),
            EHObjectSyncClassName : NSStringFromClass(managedObject.class),
            EHObjectSyncDate : NSDate.date
        };
        NSLog(@"OBJECT SYNC: Object Inserted: %@", EHLogStringFromObjectIDAndSyncDictionary(objectID, syncDictionary));
        [self.syncRequestDictionary setObject:syncDictionary forKey:objectID];
    }
    
    // Deleted Objects
    for (NSManagedObject *managedObject in deletedObjects) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingClass(self.mutableSyncDescriptors, managedObject.class);
        if (!syncDescriptor) continue;
        
        NSString *objectID = [[managedObject.objectID URIRepresentation] absoluteString];
        
        // If we have a non-remote object that's been deleted, just remove it from the dictionary
        if (self.syncRequestDictionary[objectID] && [self.syncRequestDictionary[objectID][EHObjectSyncRequestMethod] integerValue] != RKRequestMethodDELETE) {
            NSLog(@"OBJECT SYNC: Object has since deleted locally, removing from sync store dictionary: %@", managedObject);
            [self.syncRequestDictionary removeObjectForKey:objectID];
            [self saveSyncRequestDictionaryFile];
        }
        
        // Don't continue If the object doesn't exist remotely
        if ([syncDescriptor existsRemotelyBlock](managedObject) == NO) continue;
        
        // Locate the path of the object, since it will be deleted
        RKRoute *route = [self.router.routeSet routeForObject:managedObject method:RKRequestMethodDELETE];
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:route.pathPattern];
        NSString *path = [pathMatcher pathFromObject:managedObject addingEscapes:route.shouldEscapePath interpolatedParameters:nil];
        
        NSDictionary *syncDictionary = @{
            EHObjectSyncRequestMethod : RKStringFromRequestMethod(RKRequestMethodDELETE),
            EHObjectSyncClassName : NSStringFromClass(managedObject.class),
            EHObjectSyncDate : [NSDate date],
            EHObjectSyncPath : path
        };
        NSLog(@"OBJECT SYNC: Object Deleted: %@", EHLogStringFromObjectIDAndSyncDictionary(objectID, syncDictionary));
        [self.syncRequestDictionary setObject:syncDictionary forKey:objectID];
    }
    
    // Serialize the object to disk
    [self saveSyncRequestDictionaryFile];
    
    [self.managedObjectContext performBlock:^{
        [self sync];
    }];
}

- (void)sync
{
    // Don't attempt to enqueue requests if the site is not reachable
    if (self.HTTPClient.networkReachabilityStatus == AFNetworkReachabilityStatusNotReachable) {
        return;
    }
    
    // While there are pending requests, don't sync until they're finished
    if ([self.objectSyncOperationQueue operationCount]) {
        return;
    }
    
    // Suspend the queue for the creating of requests
    self.objectSyncOperationQueue.suspended = YES;
    
    // Establish a sync rank dictionation with each of the operations for that rank (keyed by rank)
    NSMutableDictionary *operationsForSyncRank = [NSMutableDictionary new];
    
    [self.syncRequestDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *objectIDStringURI, NSDictionary *objectDictionary, BOOL *stop) {
        
        EHSyncDescriptor *syncDescriptor = EHSyncDescriptorFromArrayMatchingClass(self.mutableSyncDescriptors, NSClassFromString(objectDictionary[EHObjectSyncClassName]));
        if (!syncDescriptor) return;
        
        NSLog(@"OBJECT SYNC: Building Sync Operation: %@", EHLogStringFromObjectIDAndSyncDictionary(objectIDStringURI, objectDictionary));
        
        // Add an array for this rank if it doesn't exist
        NSMutableArray *syncRankOperations = operationsForSyncRank[syncDescriptor.syncRank];
        if (!syncRankOperations) {
            syncRankOperations = [NSMutableArray new];
            operationsForSyncRank[syncDescriptor.syncRank] = syncRankOperations;
        }
        
        RKRequestMethod requestMethod = RKRequestMethodFromString(objectDictionary[EHObjectSyncRequestMethod]);
        
        EHObjectSyncOperation *objectSyncOperation = [EHObjectSyncOperation new];
        objectSyncOperation.objectSyncManager = self;
        objectSyncOperation.objectIDStringURI = objectIDStringURI;
        objectSyncOperation.syncClass = NSClassFromString(objectDictionary[EHObjectSyncClassName]);
        objectSyncOperation.syncDate = objectDictionary[EHObjectSyncDate];
        objectSyncOperation.syncRank = syncDescriptor.syncRank;
        objectSyncOperation.syncRequestMethod = requestMethod;
        
        switch (requestMethod) {
            case RKRequestMethodPOST:
            case RKRequestMethodPUT: {
                NSManagedObjectID *managedObjectID = [[self.managedObjectContext persistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:objectIDStringURI]];
                NSError *error;
                NSManagedObject *syncObject = [self.managedObjectContext existingObjectWithID:managedObjectID error:&error];
                // If we're unable to locate the object in our MOC, remove it from sync dictionary, and don't proceed
                if (!syncObject) {
                    NSLog(@"Cancelling Request, unable to find sync object: %@", [error debugDescription]);
                    [self.syncRequestDictionary removeObjectForKey:objectIDStringURI];
                    return;
                }
                objectSyncOperation.syncObject = syncObject;
                [self.objectSyncOperationQueue addOperation:objectSyncOperation];
                [syncRankOperations addObject:objectSyncOperation];
                break;
            }
            case RKRequestMethodDELETE:
                objectSyncOperation.syncPath = objectDictionary[EHObjectSyncPath];
                [self.objectSyncOperationQueue addOperation:objectSyncOperation];
                [syncRankOperations addObject:objectSyncOperation];
                break;
            default:
                NSAssert(NO, @"Unsupported request method");
                return;
                break;
        }
    }];
    
    [self saveSyncRequestDictionaryFile];
    
    // Sort requests (using dependencies) by rank
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
    
    // Start the network queue
    self.objectSyncOperationQueue.suspended = NO;
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
    switch (self.syncRequestMethod) {
        case RKRequestMethodPOST:
        case RKRequestMethodPUT:
            NSAssert(self.syncObject, @"A POST and PUT object sync request requres a sync object");
            break;
        case RKRequestMethodDELETE:
            NSAssert(self.syncPath, @"A DELETE object sync request requres a sync path");
            break;
        default:
            break;
    }
    
    switch (self.syncRequestMethod) {
        case RKRequestMethodPOST: {
            NSLog(@"Enqueueing POST (%@)", self.syncClass);
            RKObjectRequestOperation *POSTRequestOperation = [[EHObjectSyncManager sharedManager] appropriateObjectRequestOperationWithObject:self.syncObject method:self.syncRequestMethod path:nil parameters:nil];
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
            RKObjectRequestOperation *PUTRequestOperation = [[EHObjectSyncManager sharedManager] appropriateObjectRequestOperationWithObject:self.syncObject method:self.syncRequestMethod path:nil parameters:nil];
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
            NSURLRequest *deleteRequest = [(AFHTTPClient *)[EHObjectSyncManager sharedManager] requestWithMethod:RKStringFromRequestMethod(self.syncRequestMethod) path:self.syncPath parameters:nil];
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

- (void)cleanupRequest
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
    
    if ([(AFHTTPRequestOperation *)self.syncRequestOperation error]) {
        NSLog(@"Request Failed, cancelling all further request operations");
        [self.objectSyncManager.operationQueue cancelAllOperations];
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
    [self.objectSyncManager removeSyncDictionaryForObjectIDStringURI:self.objectIDStringURI];
}

@end
