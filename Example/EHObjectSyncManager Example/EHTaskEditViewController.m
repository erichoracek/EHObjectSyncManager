//
//  EHTaskEditViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/3/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHTaskEditViewController.h"
#import "EHTask.h"

// Reuse Identifiers
NSString *const EHTaskReuseIdentifierName = @"Name";
NSString *const EHTaskReuseIdentifierDueDate = @"Due Date";
NSString *const EHTaskReuseIdentifierComplete = @"Complete";
NSString *const EHTaskReuseIdentifierDelete = @"Delete";

@interface EHTaskEditViewController () <NSFetchedResultsControllerDelegate, UITextFieldDelegate>

@property (nonatomic, strong) NSManagedObjectContext *privateContext;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) MSCollectionViewTableLayout *collectionViewLayout;
@property (nonatomic, strong, readonly) EHTask *task;

- (void)prepareSections;

@end

@implementation EHTaskEditViewController

@dynamic task;

- (void)loadView
{
    self.collectionViewLayout = [[MSCollectionViewTableLayout alloc] init];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.collectionViewLayout];
    self.view = self.collectionView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = (self.task.isInserted ? @"New Task" : @"Edit Task");
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelObject)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStylePlain target:self action:@selector(saveObject)];
    
    self.collectionView.backgroundColor = [UIColor whiteColor];
    
    [self prepareSections];
}

#pragma mark - EHManagedObjectEditViewController

- (NSEntityDescription *)entityInContext:(NSManagedObjectContext *)context;
{
    return [NSEntityDescription entityForName:@"Task" inManagedObjectContext:context];
}

- (void)didSaveObject
{
    self.dismissBlock();
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
    self.dismissBlock();
}

- (void)willDeleteObjectWithCompletion:(void (^)(void))completion
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Warning" message:@"Are you sure you want to delete this task?" delegate:nil cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
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

#pragma mark - EHTaskEditViewController

- (EHTask *)task
{
    return self.fetchedResultsController.fetchedObjects[0];
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
            if (weakSelf.task.dueAt) {
                static NSDateFormatter *dateFormatter;
                if (!dateFormatter) {
                    dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateFormat:@"EEE, MMM d 'at' h:mm a"];
                }
                cell.detail.text = [dateFormatter stringFromDate:weakSelf.task.dueAt];
            } else {
                cell.detail.text = @"None";
            }
            },
            MSTableItemSelectionBlock : ^(NSIndexPath *indexPath) {
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
    
    // Delete
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
    [self.collectionView deselectItemAtIndexPath:self.collectionView.indexPathsForSelectedItems[0] animated:YES];
    return NO;
}

@end
