//
//  EHManagedObjectEditViewController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/5/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <UIKit/UIKit.h>

// Determines whether an instance of a managed object is being actively edited in a managed object edit view controller
BOOL EHManagedObjectEditViewControllerIsEditingOtherObject(NSManagedObject *managedObject);

@interface EHManagedObjectEditViewController : UIViewController

@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSManagedObject *targetObject;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nonatomic, strong) NSManagedObjectContext *privateContext;
@property (nonatomic, strong) NSManagedObject *privateTargetObject;

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;

- (BOOL)objectExistsRemotely;

- (void)reloadObject;
- (void)didReloadObject;
- (void)didFailReloadObjectWithError:(NSError *)error;

// Save
- (void)saveObject;
- (void)willSaveObject;
- (void)didSaveObject;
- (void)didFailSaveObjectWithError:(NSError *)error;

// Cancel
- (void)cancelObject;
- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void(^)(void))completion;
- (void)didCancelObject;

// Delete
- (void)deleteObject;
- (void)willDeleteObjectWithCompletion:(void (^)(void))completion;
- (void)didDeleteObject;
- (void)didFailDeleteObjectWithError:(NSError *)error;

// Object Updates (As observed by the NSFetchedResultsController)
- (void)objectWasUpdated;
- (void)objectWasDeleted;

- (void)obtainPermanentIdsForInsertedObjects;
- (void)refreshTargetObject;

@end
