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
#import "EHDatePickerController.h"
#import "EHStyleManager.h"

// Reuse Identifiers
NSString *const EHReminderReuseIdentifierRemindAt = @"Remind At";
NSString *const EHReminderReuseIdentifierDelete = @"Delete";

@interface EHReminderEditViewController ()

@property (nonatomic, strong) MSColectionViewStaticTableLayout *collectionViewLayout;
@property (nonatomic, strong, readonly) EHReminder *reminder;
@property (nonatomic, strong) EHTask *privateTask;
@property (nonatomic, strong) EHDatePickerController *remindAtDatePickerController;

- (void)prepareSections;

@end

@implementation EHReminderEditViewController

- (void)loadView
{
    self.collectionViewLayout = [[MSColectionViewStaticTableLayout alloc] init];
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
    }
    
    self.remindAtDatePickerController = [EHDatePickerController new];
    [self.view addSubview:self.remindAtDatePickerController.hiddenTextField];
    __weak typeof (self) weakSelf = self;
    self.remindAtDatePickerController.completionBlock = ^(EHDatePickerControllerCompletionType completionType) {
        if (completionType == EHDatePickerControllerCompletionTypeClear) {
            weakSelf.reminder.remindAt = nil;
        }
        [weakSelf prepareSections];
        [weakSelf.collectionView reloadData];
    };
    self.remindAtDatePickerController.dateChangedBlock = ^(NSDate *date) {
        weakSelf.reminder.remindAt = date;
    };
    
    self.navigationItem.title = (self.reminder.isInserted ? @"New Reminder" : @"Edit Reminder");

    self.navigationItem.leftBarButtonItem = [[EHStyleManager sharedManager] styledBarButtonItemWithSymbolsetTitle:@"\U00002421" action:^{
        [weakSelf cancelObject];
    }];
    self.navigationItem.rightBarButtonItem = [[EHStyleManager sharedManager] styledBarButtonItemWithSymbolsetTitle:@"\U00002713" action:^{
        [weakSelf saveObject];
    }];
    
    self.collectionView.backgroundColor = [UIColor colorWithHexString:@"eeeeee"];
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
    [super didSaveObject];
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    self.dismissBlock(YES);
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
    } else {
        [errorDescription appendFormat:@"%@.", [error localizedDescription]];
    }
    [[[UIAlertView alloc] initWithTitle:@"Unable to Save Reminder" message:errorDescription delegate:nil cancelButtonTitle:@"Continue" otherButtonTitles:nil] show];
}

- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void (^)(void))completion
{
    if (changes) {        
        NSString *message = [NSString stringWithFormat:@"Are you sure you want to cancel %@ this reminder? You will lose all unsaved changes.", (self.reminder.isInserted ? @"adding" : @"editing")];
        UIAlertView *alert = [UIAlertView alertViewWithTitle:@"Warning" message:message];
        [alert addButtonWithTitle:@"No" handler:nil];
        [alert addButtonWithTitle:@"Yes" handler:^{ completion(); }];
        [alert show];
    } else {
        completion();
    }
}

- (void)didCancelObject
{
    [super didCancelObject];
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    self.dismissBlock(YES);
}

- (void)willDeleteObjectWithCompletion:(void (^)(void))completion
{
    UIAlertView *alert = [UIAlertView alertViewWithTitle:@"Warning" message:@"Are you sure you want to delete this reminder?"];
    __weak typeof (self) weakSelf = self;
    [alert addButtonWithTitle:@"No" handler:nil];
    [alert addButtonWithTitle:@"Yes" handler:^{
        [weakSelf.collectionView deselectItemAtIndexPath:[[weakSelf.collectionView indexPathsForSelectedItems] lastObject] animated:YES];
        completion();
    }];
    [alert show];
}

- (void)didDeleteObject
{
    [super didDeleteObject];
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    self.dismissBlock(YES);
}

- (void)objectWasUpdated
{
    [super objectWasUpdated];
    [self prepareSections];
    [self.collectionView reloadData];
}

- (void)objectWasDeleted
{
    [super objectWasDeleted];
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    UIAlertView *alert = [UIAlertView alertViewWithTitle:@"Warning" message:@"This reminder was deleted on another device."];
    __weak typeof (self) weakSelf = self;
    [alert addButtonWithTitle:@"Continue" handler:^{ weakSelf.dismissBlock(YES); }];
    [alert show];
}

#pragma mark - EHReminderEditViewController

- (EHReminder *)reminder
{
    return (self.fetchedResultsController.fetchedObjects.count ? self.fetchedResultsController.fetchedObjects[0] : nil);
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
                cell.detail.text = (weakSelf.reminder.remindAt ? weakSelf.reminder.remindAtString : @"None");
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                if (weakSelf.reminder.remindAt) weakSelf.remindAtDatePickerController.datePicker.date = weakSelf.reminder.remindAt;
                [weakSelf.remindAtDatePickerController.hiddenTextField becomeFirstResponder];
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
