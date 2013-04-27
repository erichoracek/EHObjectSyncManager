//
//  EHTaskEditViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/3/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHTaskEditViewController.h"
#import "EHTask.h"
#import "EHReminder.h"
#import "EHReminderEditViewController.h"
#import "EHDatePickerController.h"
#import "EHStyleManager.h"

// Reuse Identifiers
NSString *const EHTaskReuseIdentifierName = @"Name";
NSString *const EHTaskReuseIdentifierDueDate = @"Due Date";
NSString *const EHTaskReuseIdentifierComplete = @"Complete";
NSString *const EHTaskReuseIdentifierNewReminder = @"New Reminder";
NSString *const EHTaskReuseIdentifierReminder = @"Reminder";
NSString *const EHTaskReuseIdentifierDelete = @"Delete";

@interface EHTaskEditViewController () <UITextFieldDelegate>

@property (nonatomic, strong) MSColectionViewStaticTableLayout *collectionViewLayout;
@property (nonatomic, strong, readonly) EHTask *task;
@property (nonatomic, strong) EHDatePickerController *dueAtDatePickerController;

- (void)prepareSections;

@end

@implementation EHTaskEditViewController

@dynamic task;

- (void)loadView
{
    self.collectionViewLayout = [[MSColectionViewStaticTableLayout alloc] init];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.collectionViewLayout];
    self.view = self.collectionView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[PDDebugger defaultInstance] addManagedObjectContext:self.privateContext withName:@"EHTaskEditViewController Context"];
    
    self.dueAtDatePickerController = [EHDatePickerController new];
    [self.view addSubview:self.dueAtDatePickerController.hiddenTextField];
    __weak typeof (self) weakSelf = self;
    self.dueAtDatePickerController.completionBlock = ^(EHDatePickerControllerCompletionType completionType) {
        if (completionType == EHDatePickerControllerCompletionTypeClear) {
            weakSelf.task.dueAt = nil;
        }
        [weakSelf.collectionView reloadData];
    };
    self.dueAtDatePickerController.dateChangedBlock = ^(NSDate *date) {
        weakSelf.task.dueAt = date;
    };
    
    self.navigationItem.title = (self.task.isInserted ? @"New Task" : @"Edit Task");

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
    return [NSEntityDescription entityForName:@"Task" inManagedObjectContext:context];
}

- (BOOL)objectExistsRemotely
{
    return (self.task.remoteID != nil);
}

- (void)didSaveObject
{
    [super didSaveObject];
    [[PDDebugger defaultInstance] removeManagedObjectContext:self.privateContext];
    self.dismissBlock(YES);
}

- (void)didFailSaveObjectWithError:(NSError *)error
{
    NSLog(@"Failed to save task with error: %@", [error debugDescription]);
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
    [[[UIAlertView alloc] initWithTitle:@"Unable to Save Task" message:errorDescription delegate:nil cancelButtonTitle:@"Continue" otherButtonTitles:nil] show];
}

- (void)willCancelObjectWithChanges:(BOOL)changes completion:(void (^)(void))completion
{
    if (changes) {
        NSString *message = [NSString stringWithFormat:@"Are you sure you want to cancel %@ this task? You will lose all unsaved changes.", (self.task.isInserted ? @"adding" : @"editing")];
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
    UIAlertView *alert = [UIAlertView alertViewWithTitle:@"Warning" message:@"Are you sure you want to delete this task?"];
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
    UIAlertView *alert = [UIAlertView alertViewWithTitle:@"Warning" message:@"This task was deleted on another device."];
    __weak typeof (self) weakSelf = self;
    [alert addButtonWithTitle:@"Continue" handler:^{ weakSelf.dismissBlock(YES); }];
    [alert show];
}

#pragma mark - EHTaskEditViewController

- (EHTask *)task
{
    return (self.fetchedResultsController.fetchedObjects.count ? self.fetchedResultsController.fetchedObjects[0] : nil);
}

- (void)prepareSections
{
    NSMutableArray *sections = [NSMutableArray new];
    __weak typeof (self) weakSelf = self;
    
    // Name
    [sections addObject:@{
        MSTableSectionRows : @[ @{
            MSTableReuseIdentifer : EHTaskReuseIdentifierName,
            MSTableClass : MSTextFieldGroupedTableViewCell.class,
            MSTableConfigurationBlock : ^(MSTextFieldGroupedTableViewCell *cell){
                cell.textField.text = weakSelf.task.name;
                cell.textField.keyboardAppearance = UIKeyboardAppearanceAlert;
                cell.textField.returnKeyType = UIReturnKeyDone;
                cell.textField.userInteractionEnabled = NO;
                cell.textField.delegate = weakSelf;
                cell.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Name" attributes:@{NSForegroundColorAttributeName: [UIColor colorWithHexString:@"999999"]}];
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                MSTextFieldGroupedTableViewCell *cell = (MSTextFieldGroupedTableViewCell *)[weakSelf.collectionView cellForItemAtIndexPath:indexPath];
                cell.textField.userInteractionEnabled = YES;
                [cell.textField becomeFirstResponder];
            }
         }]
     }];
    
    // Due Date
    [sections addObject:@{
        MSTableSectionRows : @[ @{
            MSTableReuseIdentifer : EHTaskReuseIdentifierDueDate,
            MSTableClass : MSRightDetailGroupedTableViewCell.class,
            MSTableConfigurationBlock : ^(MSRightDetailGroupedTableViewCell *cell){
                cell.title.text = @"Due";
                cell.detail.text = weakSelf.task.dueAtString;
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                if (weakSelf.task.dueAt) (weakSelf.dueAtDatePickerController.datePicker.date = weakSelf.task.dueAt);
                [weakSelf.dueAtDatePickerController.hiddenTextField becomeFirstResponder];
            }
         }]
     }];
    
    // Complete
    [sections addObject:@{
        MSTableSectionRows : @[ @{
            MSTableReuseIdentifer : EHTaskReuseIdentifierComplete,
            MSTableClass : MSGroupedTableViewCell.class,
            MSTableConfigurationBlock : ^(MSGroupedTableViewCell *cell){
                cell.title.text = @"Complete";
                cell.accessoryType = (weakSelf.task.completed ? MSTableCellAccessoryCheckmark : MSTableCellAccessoryNone);
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                weakSelf.task.completed = !weakSelf.task.completed;
                double delayInSeconds = 0.3;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [weakSelf.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                });
            }
         }]
     }];
    
    // Reminders
    {
        NSMutableArray *rows = [NSMutableArray new];
        
        [rows addObject: @{
            MSTableReuseIdentifer : EHTaskReuseIdentifierNewReminder,
            MSTableClass : MSGroupedTableViewCell.class,
            MSTableConfigurationBlock : ^(MSGroupedTableViewCell *cell){
                cell.title.text = @"New Reminder";
                cell.accessoryType = MSTableCellAccessoryDisclosureIndicator;
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                EHReminderEditViewController *reminderEditViewController = [[EHReminderEditViewController alloc] init];
                reminderEditViewController.task = weakSelf.task;
                reminderEditViewController.managedObjectContext = weakSelf.privateContext;
                reminderEditViewController.dismissBlock = ^(BOOL animated){
                    [weakSelf dismissViewControllerAnimated:animated completion:^{
                        [weakSelf.collectionView deselectItemAtIndexPath:[[weakSelf.collectionView indexPathsForSelectedItems] lastObject] animated:YES];
                    }];
                };
                UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:reminderEditViewController];
                [weakSelf presentViewController:navigationController animated:YES completion:nil];
            }
        }];
        
        for (EHReminder *reminder in self.task.reminders) {
            [rows addObject: @{
                MSTableReuseIdentifer : EHTaskReuseIdentifierReminder,
                MSTableClass : MSGroupedTableViewCell.class,
                MSTableConfigurationBlock : ^(MSGroupedTableViewCell *cell){
                    cell.title.text = reminder.remindAtString;
                    [cell setTitleTextAttributes:@{ UITextAttributeFont : [UIFont systemFontOfSize:17.0]} forState:UIControlStateNormal];
                    cell.accessoryType = MSTableCellAccessoryDisclosureIndicator;
                },
                MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
                    EHReminderEditViewController *reminderEditViewController = [[EHReminderEditViewController alloc] init];
                    reminderEditViewController.targetObject = reminder;
                    reminderEditViewController.managedObjectContext = weakSelf.privateContext;
                    reminderEditViewController.dismissBlock = ^(BOOL animated){
                        [weakSelf.navigationController popViewControllerAnimated:animated];
                        double delayInSeconds = 0.3;
                        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                            [weakSelf.collectionView deselectItemAtIndexPath:[[weakSelf.collectionView indexPathsForSelectedItems] lastObject] animated:YES];
                        });
                    };
                    [weakSelf.navigationController pushViewController:reminderEditViewController animated:YES];
                }
            }];
        }
        
        [sections addObject:@{
             MSTableSectionRows : rows
        }];
    }
    
    // Delete
    if (!self.task.isInserted) {
        [sections addObject:@{
            MSTableSectionRows : @[ @{
                MSTableReuseIdentifer : EHTaskReuseIdentifierDelete,
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

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    self.task.name = textField.text;
    textField.userInteractionEnabled = NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.view endEditing:YES];
    [self.collectionView deselectItemAtIndexPath:[[self.collectionView indexPathsForSelectedItems] lastObject] animated:YES];
    return NO;
}

@end
