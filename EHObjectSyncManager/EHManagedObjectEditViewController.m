//
//  EHManagedObjectEditViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/5/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHManagedObjectEditViewController.h"

@interface EHManagedObjectEditViewController () <NSFetchedResultsControllerDelegate>

- (void)obtainPermanentIdsForInsertedObjects;
- (void)refreshTargetObject;

@end

@implementation EHManagedObjectEditViewController

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSParameterAssert(self.managedObjectContext);
    
    self.privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.privateContext performBlockAndWait:^{
        self.privateContext.parentContext = self.managedObjectContext;
        self.privateContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    }];
    
    NSParameterAssert([self entityInContext:self.privateContext]);
    
    // If there's no target object, insert one into the private context
    if (!self.targetObject) {
        [self.privateContext performBlockAndWait:^{
            self.privateTargetObject = [[NSManagedObject alloc] initWithEntity:[self entityInContext:self.privateContext] insertIntoManagedObjectContext:self.privateContext];
        }];
    }
    // If a target object exists, locate it in the private context by object ID
    else {
        NSAssert([self.targetObject isKindOfClass:[NSManagedObject class]], @"Target object is not a managed object");
        NSAssert((self.targetObject.managedObjectContext == self.managedObjectContext), @"Target object is not a member of the managed object context");
        __block NSError *error;
        [self.privateContext performBlockAndWait:^{
            self.privateTargetObject = [self.privateContext existingObjectWithID:self.targetObject.objectID error:&error];
            if (error) {
                NSLog(@"Error finding private target object in private context, error %@", [error debugDescription]);
            }
            NSAssert(self.privateTargetObject, @"Unable to find object in private context, unable to proceed");
        }];
    }
    
    // Prepare a fetch request to monitor the target object
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.fetchLimit = 1;
    fetchRequest.sortDescriptors = @[ ];
    fetchRequest.entity = [self entityInContext:self.privateContext];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(SELF == %@)", self.privateTargetObject];
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.privateContext sectionNameKeyPath:nil cacheName:nil];
    self.fetchedResultsController.delegate = self;
    NSError *error;
    BOOL fetchSuccessful = [self.fetchedResultsController performFetch:&error];
    NSAssert2(fetchSuccessful, @"Unable to fetch %@, %@", fetchRequest.entityName, [error debugDescription]);
}

#pragma mark - EHManagedObjectEditViewController

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;
{
    return nil;
}

- (void)obtainPermanentIdsForInsertedObjects
{
    // Obtain a permanent ID for the private object before proceeding
    static NSPredicate *temporaryObjectsPredicate = nil;
    if (!temporaryObjectsPredicate) temporaryObjectsPredicate = [NSPredicate predicateWithFormat:@"objectID.isTemporaryID == YES"];
    NSSet *temporaryObjects = [[self.privateContext insertedObjects] filteredSetUsingPredicate:temporaryObjectsPredicate];
    if (temporaryObjects.count) {
        NSLog(@"Obtaining permanent IDs for inserted objects");
        __block BOOL success;
        __block NSError *error;
        [self.privateContext performBlockAndWait:^{
            success = [self.privateContext obtainPermanentIDsForObjects:[temporaryObjects allObjects] error:&error];
        }];
        if (!success) NSLog(@"Failed to obtain permanent ID for objects %@ with error %@", temporaryObjects, error);
    }
}

- (void)refreshTargetObject
{
    [self.managedObjectContext performBlock:^{
        NSLog(@"Refreshing mapped target object %@ in context %@", self.targetObject, self.managedObjectContext);
        [self.managedObjectContext refreshObject:self.targetObject mergeChanges:YES];
    }];
}

- (void)cancelObject
{
    [self willCancelObjectWithChanges:[self.privateContext hasChanges] completion:^{
        [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
        [self didCancelObject];
    }];
}

- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void(^)(void))completion;
{
    
}

- (void)didCancelObject
{
    NSLog(@"Successfully cancelled %@", self.targetObject);
}

- (void)saveObject
{
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    [self willSaveObject];
    [self obtainPermanentIdsForInsertedObjects];
    NSError* error;
    if(![self.privateContext saveToPersistentStore:&error]) {
        [self didFailSaveObjectWithError:error];
    } else {
        [self didSaveObject];
    }
    [self refreshTargetObject];
}

- (void)willSaveObject
{
    
}

- (void)didSaveObject
{
    NSLog(@"Successfully saved %@", self.targetObject);
}

- (void)didFailSaveObjectWithError:(NSError *)error
{
    NSLog(@"Failed to save %@ with error %@", self.targetObject, [error debugDescription]);
}

- (void)deleteObject
{
    [self willDeleteObjectWithCompletion:^{
        [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
        [self.privateContext performBlockAndWait:^{
            [self.privateContext deleteObject:self.privateTargetObject];
        }];
        NSError *error = nil;
        if ([self.privateContext saveToPersistentStore:&error]) {
            [self didDeleteObject];
        } else {
            [self didFailDeleteObjectWithError:error];
        }
        [self refreshTargetObject];
    }];
}

- (void)willDeleteObjectWithCompletion:(void (^)(void))completion
{
    
}

- (void)didDeleteObject
{
    
}

- (void)didFailDeleteObjectWithError:(NSError *)error
{
    
}

@end
