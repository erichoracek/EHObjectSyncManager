//
//  EHTasksViewController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHTasksViewController.h"
#import "EHTaskEditViewController.h"
#import "EHObjectSyncManager.h"
#import "EHTask.h"
#import "EHStyleManager.h"
#import "EHEtchView.h"

NSString * const EHTaskCellReuseIdentifier = @"EHTaskCellReuseIdentifier";
NSString * const EHEtchReuseIdentifier = @"EHEtchReuseIdentifier";

@interface EHTasksViewController () <NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) MSCollectionViewTableLayout *collectionViewLayout;

- (void)loadData;
- (void)applicationDidBecomeActive:(NSNotification *)notification;

@end

@implementation EHTasksViewController

#pragma mark - NSObject

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIViewController

- (void)loadView
{
    self.collectionViewLayout = [[MSCollectionViewTableLayout alloc] init];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.collectionViewLayout];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Task"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"completedAt" ascending:NO]];
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.managedObjectContext sectionNameKeyPath:nil cacheName:nil];
    self.fetchedResultsController.delegate = self;
    NSError *error;
    BOOL fetchSuccessful = [self.fetchedResultsController performFetch:&error];
    NSAssert2(fetchSuccessful, @"Unable to fetch %@, %@", fetchRequest.entityName, [error debugDescription]);
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor colorWithHexString:@"222222"];
    [self.refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    [self.collectionView addSubview:self.refreshControl];
    
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.backgroundColor = [UIColor colorWithHexString:@"eeeeee"];
    [self.collectionView registerClass:MSSubtitleDetailPlainTableViewCell.class forCellWithReuseIdentifier:EHTaskCellReuseIdentifier];
    [self.collectionViewLayout registerClass:MSTableCellEtch.class forDecorationViewOfKind:MSCollectionElementKindCellEtch];
    
    self.navigationItem.title = @"Tasks";
    
    __weak typeof (self) weakSelf = self;
    self.navigationItem.rightBarButtonItem = [[EHStyleManager sharedManager] styledBarButtonItemWithSymbolsetTitle:@"+" action:^{
        EHTaskEditViewController *taskEditViewController = [[EHTaskEditViewController alloc] init];
        taskEditViewController.managedObjectContext = weakSelf.managedObjectContext;
        taskEditViewController.dismissBlock = ^(BOOL animated){
            [weakSelf dismissViewControllerAnimated:animated completion:nil];
        };
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:taskEditViewController];
        [weakSelf presentViewController:navigationController animated:YES completion:nil];
    }];
}

#pragma mark - EHTasksViewController

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self loadData];
}

- (void)loadData
{
    __weak typeof(self) weakSelf = self;
    
    [[RKObjectManager sharedManager] getObjectsAtPath:@"/tasks.json" parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        [weakSelf.refreshControl endRefreshing];
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        [weakSelf.refreshControl endRefreshing];
        NSLog(@"Task load failed with error: %@", error);
    }];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return self.fetchedResultsController.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController.sections objectAtIndex:section];
    return sectionInfo.numberOfObjects;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    MSTableCell *cell = [self.collectionView dequeueReusableCellWithReuseIdentifier:EHTaskCellReuseIdentifier forIndexPath:indexPath];
    EHTask *task = [self.fetchedResultsController objectAtIndexPath:indexPath];
    cell.title.text = task.name;
    cell.detail.text = (task.dueAt ? [NSString stringWithFormat:@"Due %@", task.dueAtString] : nil);
    cell.accessoryType = (task.completed ? MSTableCellAccessoryCheckmark : MSTableCellAccessoryNone);
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    EHTask *task = [self.fetchedResultsController objectAtIndexPath:indexPath];
    
    EHTaskEditViewController *taskEditViewController = [[EHTaskEditViewController alloc] init];
    taskEditViewController.targetObject = task;
    taskEditViewController.managedObjectContext = self.managedObjectContext;
    __weak typeof (self) weakSelf = self;
    taskEditViewController.dismissBlock = ^(BOOL animated){
        [weakSelf.navigationController popViewControllerAnimated:animated];
    };
    
    [self.navigationController pushViewController:taskEditViewController animated:YES];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return (CGSize){CGRectGetWidth(self.collectionView.frame), [MSSubtitleDetailPlainTableViewCell height]};
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    return 0.0;
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

@end
