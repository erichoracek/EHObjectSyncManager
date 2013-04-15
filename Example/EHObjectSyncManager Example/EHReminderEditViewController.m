//
//  EHReminderEditViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/13/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHReminderEditViewController.h"
#import "EHReminder.h"
#import "EHTask.h"

// Reuse Identifiers
NSString *const EHReminderReuseIdentifierRemindAt = @"Remind At";
NSString *const EHReminderReuseIdentifierDelete = @"Delete";

@interface EHReminderEditViewController ()

@property (nonatomic, strong) MSCollectionViewTableLayout *collectionViewLayout;
@property (nonatomic, strong, readonly) EHReminder *reminder;
@property (nonatomic, strong) EHTask *privateTask;

- (void)prepareSections;

@end

@implementation EHReminderEditViewController

- (void)loadView
{
    self.collectionViewLayout = [[MSCollectionViewTableLayout alloc] init];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.collectionViewLayout];
    self.view = self.collectionView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[PDDebugger defaultInstance] addManagedObjectContext:self.privateContext withName:@"EHReminderEditViewController Context"];
    
    if (self.reminder.isInserted) {
        NSAssert(self.task, @"A new reminder requires a task");
        NSAssert((self.task.managedObjectContext == self.managedObjectContext), @"Task object is not a member of the managed object context");
        [self.privateContext performBlockAndWait:^{
            NSError *error;
            self.privateTask = (EHTask *)[self.privateContext existingObjectWithID:self.task.objectID error:&error];
            if (error) {
                NSLog(@"Error finding private task object in private context: %@", [error debugDescription]);
            }
            NSAssert(self.privateTask, @"Unable to find task in private context, unable to proceed");
        }];
        self.reminder.task = self.privateTask;
        self.reminder.remindAt = [NSDate date];
    }
    
    self.navigationItem.title = (self.reminder.isInserted ? @"New Reminder" : @"Edit Reminder");
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelObject)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStylePlain target:self action:@selector(saveObject)];
    
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self prepareSections];
}

#pragma mark - EHManagedObjectEditViewController

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;
{
    return [NSEntityDescription entityForName:@"Reminder" inManagedObjectContext:context];
}

- (BOOL)objectExistsRemotely
{
    return (self.reminder.remoteID != nil);
}

- (void)didSaveObject
{
    self.dismissBlock();
}

- (void)didFailSaveObjectWithError:(NSError *)error
{
    NSLog(@"Failed to save reminder with error: %@", [error debugDescription]);
    NSMutableString *errorDescription = [NSMutableString string];
    NSArray* detailedErrors = [error.userInfo objectForKey:NSDetailedErrorsKey];
    if(detailedErrors && detailedErrors.count != 0) {
        for(NSError* detailedError in detailedErrors) {
            NSLog(@"Error: %@", [detailedError debugDescription]);
            [errorDescription appendFormat:@"%@. ", [detailedError localizedDescription]];
        }
    }
    else {
        [errorDescription appendFormat:@"%@.", [error localizedDescription]];
    }
    [[[UIAlertView alloc] initWithTitle:@"Unable to Save Reminder" message:errorDescription delegate:nil cancelButtonTitle:@"Continue" otherButtonTitles:nil] show];
}

- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void (^)(void))completion
{
    if (changes) {
        NSString *message = [NSString stringWithFormat:@"Are you sure you want to cancel %@ this reminder? You will lose all unsaved changes.", (self.reminder.isInserted ? @"adding" : @"editing")];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Warning" message:message delegate:nil cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
        A2DynamicDelegate *dynamicDelegate = alert.dynamicDelegate;
        [dynamicDelegate implementMethod:@selector(alertView:didDismissWithButtonIndex:) withBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
            if (buttonIndex == 1) completion();
        }];
        alert.delegate = dynamicDelegate;
        [alert show];
    } else {
        completion();
    }
}

- (void)didCancelObject
{
    [super didCancelObject];
    self.dismissBlock();
}

- (void)willDeleteObjectWithCompletion:(void (^)(void))completion
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Warning" message:@"Are you sure you want to delete this reminder?" delegate:nil cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
    A2DynamicDelegate *dynamicDelegate = alert.dynamicDelegate;
    [dynamicDelegate implementMethod:@selector(alertView:didDismissWithButtonIndex:) withBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == 1) completion();
    }];
    alert.delegate = dynamicDelegate;
    [alert show];
}

- (void)didDeleteObject
{
    self.dismissBlock();
}

#pragma mark - EHReminderEditViewController

- (EHReminder *)reminder
{
    return self.fetchedResultsController.fetchedObjects[0];
}

- (void)prepareSections
{
    NSMutableArray *sections = [NSMutableArray new];
    __weak typeof (self) weakSelf = self;
    
    // Due Date
    [sections addObject:@{
        MSTableSectionRows : @[ @{
            MSTableReuseIdentifer : EHReminderReuseIdentifierRemindAt,
            MSTableClass : MSRightDetailGroupedTableViewCell.class,
            MSTableConfigurationBlock : ^(MSRightDetailGroupedTableViewCell *cell){
                cell.title.text = @"Remind At";
                cell.detail.text = weakSelf.reminder.remindAtString;
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
            }
        }]
    }];
    
    // Delete
    if (!self.reminder.isInserted) {
        [sections addObject:@{
            MSTableSectionRows : @[ @{
                MSTableReuseIdentifer : EHReminderReuseIdentifierDelete,
                MSTableClass : MSButtonGroupedTableViewCell.class,
                MSTableConfigurationBlock : ^(MSButtonGroupedTableViewCell *cell){
                    cell.title.text = @"Delete";
                    cell.buttonBackgroundColor = [UIColor colorWithHexString:@"FFB3B3"];
                },
                MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                    [weakSelf deleteObject];
                }
            }]
        }];
    }
    
    self.collectionViewLayout.sections = sections;
}

@end
