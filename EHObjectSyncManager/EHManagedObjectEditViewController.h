//
//  EHManagedObjectEditViewController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/5/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface EHManagedObjectEditViewController : UIViewController

@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSManagedObject *targetObject;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nonatomic, strong) NSManagedObjectContext *privateContext;
@property (nonatomic, strong) NSManagedObject *privateTargetObject;

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;

- (void)cancelObject;
- (void)saveObject;
- (void)deleteObject;

// Save
- (void)willSaveObject;
- (void)didSaveObject;
- (void)didFailSaveObjectWithError:(NSError *)error;

// Cancel
- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void(^)(void))completion;
- (void)didCancelObject;

// Delete
- (void)willDeleteObjectWithCompletion:(void (^)(void))completion;
- (void)didDeleteObject;
- (void)didFailDeleteObjectWithError:(NSError *)error;

@end
