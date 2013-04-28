//
//  EHManagedObjectEditViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/5/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHManagedObjectEditViewController.h"
#import "EHObjectSyncManager.h"

NSString * const EHEditedObjectID = @"EHEditedObjectID";
BOOL EHManagedObjectEditViewControllerIsEditingOtherObject(NSManagedObject *managedObject)
{
    return (managedObject.managedObjectContext.userInfo[EHEditedObjectID] && ![managedObject.managedObjectContext.userInfo[EHEditedObjectID] isEqual:managedObject.objectID]);
}

@interface EHManagedObjectEditViewController () <NSFetchedResultsControllerDelegate>

@property (nonatomic, assign) BOOL disableMergeForNestedSave;

- (void)handleManagedObjectContextDidSaveNotification:(NSNotification *)notification;
- (void)savePrivateContextWithCompletion:(void (^)(BOOL success, NSError *error))completion;
- (void)obtainPermanentIdsForInsertedObjects;
- (void)refreshTargetObject;

@end

@implementation EHManagedObjectEditViewController

#pragma mark - UIViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSParameterAssert(self.managedObjectContext);
    
    self.privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.privateContext performBlockAndWait:^{
        self.privateContext.parentContext = self.managedObjectContext;
        self.privateContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleManagedObjectContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:self.privateContext.parentContext];
    
    NSParameterAssert([self entityInContext:self.privateContext]);
    
    // If there's no target object, insert one into the private context
    if (!self.targetObject) {
        [self.privateContext performBlockAndWait:^{
            self.privateTargetObject = [[NSManagedObject alloc] initWithEntity:[self entityInContext:self.privateContext] insertIntoManagedObjectContext:self.privateContext];
        }];
        [self obtainPermanentIdsForInsertedObjects];
    }
    // If a target object exists, locate it in the private context by object ID
    else {
        NSAssert([self.targetObject isKindOfClass:[NSManagedObject class]], @"Target object is not a managed object");
        NSAssert((self.targetObject.managedObjectContext == self.managedObjectContext), @"Target object is not a member of the managed object context");
        [self.privateContext performBlockAndWait:^{
            NSError *error;
            self.privateTargetObject = [self.privateContext existingObjectWithID:self.targetObject.objectID error:&error];
            if (error) {
                NSLog(@"Error finding private target object in private context, error %@", [error debugDescription]);
            }
            NSAssert(self.privateTargetObject, @"Unable to find object in private context, unable to proceed");
        }];
    }
    
    self.privateContext.userInfo[EHEditedObjectID] = self.privateTargetObject.objectID;
    
    // Prepare a fetch request to monitor the target object
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.fetchLimit = 1;
    fetchRequest.sortDescriptors = @[ ]; // Required by NSFetchedResultsController
    fetchRequest.entity = [self entityInContext:self.privateContext];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(SELF == %@)", self.privateTargetObject];
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.privateContext sectionNameKeyPath:nil cacheName:nil];
    self.fetchedResultsController.delegate = self;
    NSError *error;
    BOOL fetchSuccessful = [self.fetchedResultsController performFetch:&error];
    NSAssert2(fetchSuccessful, @"Unable to fetch %@, %@", fetchRequest.entityName, [error debugDescription]);
    
    [self reloadObject];
}

#pragma mark - EHManagedObjectEditViewController

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;
{
    NSAssert(NO, @"Subclasses should override this method");
    return nil;
}

- (BOOL)objectExistsRemotely
{
    NSAssert(NO, @"Subclasses should override this method");
    return NO;
}

- (void)handleManagedObjectContextDidSaveNotification:(NSNotification *)notification
{
    NSAssert([notification object] == self.privateContext.parentContext, @"Received Managed Object Context Did Save Notification for Unexpected Context: %@", [notification object]);
    if (self.disableMergeForNestedSave) return;
    [self.privateContext performBlock:^{
        NSLog(@"MERGING CHANGES FROM PARENT CONTEXT: %@", notification);
        [self.privateContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (void)savePrivateContextWithCompletion:(void (^)(BOOL success, NSError *error))completion
{
    __block NSError* error;
    __block BOOL success;
    
    if ([[EHObjectSyncManager sharedManager] managedObjectContext] == self.managedObjectContext) {
        [self obtainPermanentIdsForInsertedObjects];
        self.disableMergeForNestedSave = YES;
        success = [self.privateContext saveToPersistentStore:&error];
        self.disableMergeForNestedSave = NO;
    } else {
        [self.privateContext performBlockAndWait:^{
            success = [self.privateContext save:&error];
        }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(success, error);
    });
}

- (void)obtainPermanentIdsForInsertedObjects
{
    // Obtain a permanent ID for the private object before proceeding
    static NSPredicate *temporaryObjectsPredicate = nil;
    if (!temporaryObjectsPredicate) temporaryObjectsPredicate = [NSPredicate predicateWithFormat:@"objectID.isTemporaryID == YES"];
    NSSet *temporaryObjects = [[self.privateContext insertedObjects] filteredSetUsingPredicate:temporaryObjectsPredicate];
    if (temporaryObjects.count) {
        __block BOOL success;
        __block NSError *error;
        [self.privateContext performBlockAndWait:^{
            success = [self.privateContext obtainPermanentIDsForObjects:[temporaryObjects allObjects] error:&error];
        }];
        if (!success) NSLog(@"Failed to obtain permanent ID for objects %@ with error %@", [temporaryObjects valueForKey:@"objectID"], error);
        else NSLog(@"Successfully obtained permanent ID for objects %@", [temporaryObjects valueForKey:@"objectID"]);
    }
}

- (void)reloadObject
{
    __weak typeof(self) weakSelf = self;
    // Don't load objects that don't exist remotely
    if (![self objectExistsRemotely]) {
        return;
    }
    [[RKObjectManager sharedManager] getObject:self.privateTargetObject path:nil parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        [weakSelf didReloadObject];
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        if (operation.HTTPRequestOperation.response.statusCode == 404) {
            NSLog(@"Received 404 for managed object, deleting...");
            [self.privateContext performBlockAndWait:^{
                [self.privateContext deleteObject:self.privateTargetObject];
            }];
            [self savePrivateContextWithCompletion:^(BOOL success, NSError *error) {
                if (!success) NSLog(@"Failed to delete object in private context with error %@", error);
            }];
        }
        [weakSelf didFailReloadObjectWithError:error];
    }];
}

- (void)didReloadObject
{
    
}

- (void)didFailReloadObjectWithError:(NSError *)error
{
    
}

- (void)refreshTargetObject
{
    [self.managedObjectContext performBlock:^{
        NSLog(@"Refreshing target object (%@)", self.targetObject.objectID);
        [self.managedObjectContext refreshObject:self.targetObject mergeChanges:YES];
    }];
}

- (void)cancelObject
{
    [self willCancelObjectWithChanges:[self.privateContext hasChanges] completion:^{
        [self didCancelObject];
    }];
}

- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void(^)(void))completion;
{
    
}

- (void)didCancelObject
{
    NSLog(@"Successfully cancelled %@", self.targetObject.objectID);
}

- (void)saveObject
{
    [self willSaveObject];
    // Prevent fetched results controller delegate callbacks during our private context's save
    self.fetchedResultsController.delegate = nil;
    [self savePrivateContextWithCompletion:^(BOOL success, NSError *error) {
        // Re-enable fetched results controller delegate callbacks during our private context's save
        self.fetchedResultsController.delegate = self;
        if (success) {
            [self didSaveObject];
        } else {
            [self didFailSaveObjectWithError:error];
        }
        [self refreshTargetObject];
    }];
}

- (void)willSaveObject
{
    
}

- (void)didSaveObject
{
    NSLog(@"Successfully saved (%@)", self.targetObject.objectID);
}

- (void)didFailSaveObjectWithError:(NSError *)error
{
    NSLog(@"Failed to save %@ with error %@", self.targetObject.objectID, [error debugDescription]);
}

- (void)deleteObject
{
    [self willDeleteObjectWithCompletion:^{
        // Prevent fetched results controller delegate callbacks during our private context's save
        self.fetchedResultsController.delegate = nil;
        [self.privateContext performBlockAndWait:^{
            [self.privateContext deleteObject:self.privateTargetObject];
        }];
        [self savePrivateContextWithCompletion:^(BOOL success, NSError *error) {
            // Re-enable fetched results controller delegate callbacks during our private context's save
            self.fetchedResultsController.delegate = self;
            if (success) {
                [self didDeleteObject];
            } else {
                [self didFailDeleteObjectWithError:error];
            }
            [self refreshTargetObject];
        }];
    }];
}

- (void)willDeleteObjectWithCompletion:(void (^)(void))completion
{
    
}

- (void)didDeleteObject
{
    NSLog(@"Successfully deleted (%@)", self.targetObject.objectID);
}

- (void)didFailDeleteObjectWithError:(NSError *)error
{
    NSLog(@"Failed to delete %@ with error %@", self.targetObject.objectID, [error debugDescription]);
}

- (void)objectWasDeleted
{
    NSLog(@"Target object was deleted (%@)", self.privateTargetObject.objectID);
}

- (void)objectWasUpdated
{
    NSLog(@"Target object was updated (%@)", self.privateTargetObject.objectID);
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath
{
    NSAssert(anObject == self.privateTargetObject, @"Fetched Results Controller not observing target object");
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (type) {
            case NSFetchedResultsChangeDelete:
                [self objectWasDeleted];
                break;
            case NSFetchedResultsChangeUpdate:
                [self objectWasUpdated];
                break;
        }
    });
}

@end
