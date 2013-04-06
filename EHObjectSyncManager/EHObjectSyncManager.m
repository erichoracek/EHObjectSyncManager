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
NSString * const EHObjectSyncRank = @"EHObjectSyncRequestUserDataRank";
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

- (void)handlePersistentStoreManagedObjectContextDidSaveNotification:(NSNotification *)notification;
- (void)handleManagedObjectContextDidSaveNotification:(NSNotification *)notification;

- (void)sync;
- (NSString *)logStringForObjectSyncDictionary:(NSDictionary *)dictionary objectID:(NSString *)objectID;

@end

@implementation EHObjectSyncManager

- (id)initWithHTTPClient:(AFHTTPClient *)client
{
    self = [super initWithHTTPClient:client];
    if (self) {
        self.mutableSyncDescriptors = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureSyncManagerWithManagedObjectStore:(RKManagedObjectStore *)managedObjectStore
{
    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    self.managedObjectContext.parentContext = managedObjectStore.persistentStoreManagedObjectContext;
    self.managedObjectContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleManagedObjectContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePersistentStoreManagedObjectContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext.parentContext];
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

- (void)handleManagedObjectContextDidSaveNotification:(NSNotification *)notification
{
    NSAssert([notification object] == self.managedObjectContext, @"Received Managed Object Context Did Save Notification for Unexpected Context: %@", [notification object]);
    
//    NSSet *(^localManagedObjectContextObjects)(NSSet *objects) = ^NSSet *(NSSet *objects) {
//        NSMutableSet *localObjects = [NSMutableSet set];
//        for (NSManagedObject *fetchedObject in objects) {
//            NSManagedObject *localManagedObject = [self.managedObjectContext existingObjectWithID:fetchedObject.objectID error:nil];
//            [localObjects addObject:localManagedObject];
//        }
//        return localObjects;
//    };
//    
//    NSSet *deletedObjects = localManagedObjectContextObjects([notification.userInfo objectForKey:NSDeletedObjectsKey]);
//    NSSet *updatedObjects = localManagedObjectContextObjects([notification.userInfo objectForKey:NSUpdatedObjectsKey]);
//    NSSet *insertedObjects = localManagedObjectContextObjects([notification.userInfo objectForKey:NSInsertedObjectsKey]);
//    
//    if ((updatedObjects.count == 0) && (insertedObjects.count == 0) && (deletedObjects.count == 0)) {
//        RKLogCritical(@"No changes, returning");
//        return;
//    } else {
//        if (updatedObjects.count) NSLog(@"Updated Objects %@", updatedObjects);
//        if (insertedObjects.count) NSLog(@"Inserted Objects %@", insertedObjects);
//        if (deletedObjects.count) NSLog(@"Deleted Objects %@", deletedObjects);
//    }
    
    NSSet *deletedObjects = [notification.userInfo objectForKey:NSDeletedObjectsKey];
    NSSet *updatedObjects = [notification.userInfo objectForKey:NSUpdatedObjectsKey];
    NSSet *insertedObjects = [notification.userInfo objectForKey:NSInsertedObjectsKey];
    
    if ((updatedObjects.count == 0) && (insertedObjects.count == 0) && (deletedObjects.count == 0)) {
        RKLogCritical(@"No changes, returning");
        return;
    } else {
        if (updatedObjects.count) NSLog(@"Updated Objects %@", updatedObjects);
        if (insertedObjects.count) NSLog(@"Inserted Objects %@", insertedObjects);
        if (deletedObjects.count) NSLog(@"Deleted Objects %@", deletedObjects);
    }
    
//#warning return
//    return;
    
//    [self.managedObjectContext performBlock:^{
    
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
    if ([self.operationQueue operationCount]) {
        NSLog(@"Awaiting execution of %ld enqueued connection operations: %@", (long) [self.operationQueue operationCount], [self.operationQueue operations]);
        [self.operationQueue waitUntilAllOperationsAreFinished];
    }
    
    // If the object sync store is empty, no sync is needed
    NSDictionary *objectSyncDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore];
    if (objectSyncDictionary == nil || objectSyncDictionary.count == 0) {
        return;
    }
    NSLog(@"Sync Dictionary: %@", objectSyncDictionary);
    
//    NSMutableArray *objectSyncRequestOperations = [NSMutableArray array];
//    __block NSUInteger lowestObjectSyncRank = NSUIntegerMax;

    [objectSyncDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *objectIDStringURI, NSDictionary *objectDictionary, BOOL *stop) {
        
        RKRequestMethod syncObjectRequestMethod = [[objectDictionary objectForKey:EHObjectSyncRequestMethod] integerValue];
        
        NSManagedObject *syncObject;
        if (syncObjectRequestMethod == RKRequestMethodPOST || syncObjectRequestMethod == RKRequestMethodPUT) {
            NSManagedObjectID *managedObjectID = [[self.managedObjectContext persistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:objectIDStringURI]];
            syncObject = [self.managedObjectContext existingObjectWithID:managedObjectID error:nil];
        }
        
        // Post
        if (syncObjectRequestMethod == RKRequestMethodPOST) {
            NSLog(@"Performing POST %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            RKObjectRequestOperation *requestOperation = [self appropriateObjectRequestOperationWithObject:syncObject method:RKRequestMethodPOST path:nil parameters:nil];
            [requestOperation setCompletionBlockWithSuccess:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
                NSLog(@"POST Succeeded %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            } failure:^(RKObjectRequestOperation *operation, NSError *error) {
                NSLog(@"POST Failure %@", error);
            }];
            
            EHSyncRequestCleanupOperation *cleanupOperation = [[EHSyncRequestCleanupOperation alloc] init];
            cleanupOperation.requestOperation = requestOperation;
            cleanupOperation.objectIDStringURI = objectIDStringURI;
            [cleanupOperation addDependency:requestOperation];
            
            [self.operationQueue addOperation:requestOperation];
            [self.operationQueue addOperation:cleanupOperation];
        }
        
        // Put
        if (syncObjectRequestMethod == RKRequestMethodPUT) {
            NSLog(@"Performing PUT %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            RKObjectRequestOperation *requestOperation = [self appropriateObjectRequestOperationWithObject:syncObject method:RKRequestMethodPUT path:nil parameters:nil];
            [requestOperation setCompletionBlockWithSuccess:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
                NSLog(@"PUT Succeeded %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            } failure:^(RKObjectRequestOperation *operation, NSError *error) {
                NSLog(@"PUT Failure %@", error);
            }];
            
            EHSyncRequestCleanupOperation *cleanupOperation = [[EHSyncRequestCleanupOperation alloc] init];
            cleanupOperation.requestOperation = requestOperation;
            cleanupOperation.objectIDStringURI = objectIDStringURI;
            [cleanupOperation addDependency:requestOperation];
            
            [self.operationQueue addOperation:requestOperation];
            [self.operationQueue addOperation:cleanupOperation];
        }
        
        // Delete
        if (syncObjectRequestMethod == RKRequestMethodDELETE) {
            NSLog(@"Performing DELETE %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            NSURLRequest *syncRequest = [(AFHTTPClient *)self requestWithMethod:@"DELETE" path:objectDictionary[EHObjectSyncPath] parameters:nil];
            AFJSONRequestOperation *requestOperation = [AFJSONRequestOperation JSONRequestOperationWithRequest:syncRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                NSLog(@"DELETE Succeeded %@", [self logStringForObjectSyncDictionary:objectSyncDictionary objectID:objectIDStringURI]);
            } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                NSLog(@"DELETE Failure %@", error);
            }];
            
            EHSyncRequestCleanupOperation *cleanupOperation = [[EHSyncRequestCleanupOperation alloc] init];
            cleanupOperation.requestOperation = requestOperation;
            cleanupOperation.objectIDStringURI = objectIDStringURI;
            [cleanupOperation addDependency:requestOperation];
            
            [self.operationQueue addOperation:requestOperation];
            [self.operationQueue addOperation:cleanupOperation];
        }
    }];
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

@implementation EHSyncRequestCleanupOperation

- (void)main
{
    NSAssert([self.requestOperation isFinished], @"Request operation must be finished");
    // The request was successful
    
    if ([self.requestOperation isKindOfClass:AFJSONRequestOperation.class]) {
        AFHTTPRequestOperation *requestOperation = (AFHTTPRequestOperation *)self.requestOperation;
        if (!requestOperation.error) {
            [self removeObjectFromSyncDictionary];
        }
        if (requestOperation.response.statusCode == 404) {
            [self removeObjectFromSyncDictionary];
        }
    }
    else if ([self.requestOperation isKindOfClass:RKObjectRequestOperation.class]) {
        
        RKObjectRequestOperation *requestOperation = (RKObjectRequestOperation *)self.requestOperation;
        if (!requestOperation.error) {
            [self removeObjectFromSyncDictionary];
        }
        if (requestOperation.HTTPRequestOperation.response.statusCode == 404) {
            [self removeObjectFromSyncDictionary];
        }
    }
}

- (void)removeObjectFromSyncDictionary
{
    NSMutableDictionary *synchronizationDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:EHUserDefaultsObjectSyncStore] mutableCopy];
    NSLog(@"Removing URI %@: %@", self.objectIDStringURI, synchronizationDictionary[self.objectIDStringURI]);
    [synchronizationDictionary removeObjectForKey:self.objectIDStringURI];
    [[NSUserDefaults standardUserDefaults] setObject:synchronizationDictionary forKey:EHUserDefaultsObjectSyncStore];
}

@end
