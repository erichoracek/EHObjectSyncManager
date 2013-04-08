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

NSString * const EHTaskCellReuseIdentifier = @"EHTaskCellReuseIdentifier";

@interface EHTasksViewController () <NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) UICollectionViewFlowLayout *collectionViewLayout;

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
    self.collectionViewLayout = [[UICollectionViewFlowLayout alloc] init];
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
    [self.refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    [self.collectionView addSubview:self.refreshControl];
    
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self.collectionView registerClass:MSSubtitleDetailPlainTableViewCell.class forCellWithReuseIdentifier:EHTaskCellReuseIdentifier];
    
    self.navigationItem.title = @"Tasks";
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(new)];
    
    [self loadData];
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
        NSLog(@"Tasks loaded %@", [[mappingResult array] valueForKey:@"name"]);
    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        [weakSelf.refreshControl endRefreshing];
        NSLog(@"Task load failed with error: %@", error);
    }];
}

- (void)new
{
    EHTaskEditViewController *taskEditViewController = [[EHTaskEditViewController alloc] init];
    taskEditViewController.managedObjectContext = self.managedObjectContext;
    __weak typeof (self) weakSelf = self;
    taskEditViewController.dismissBlock = ^{
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:taskEditViewController];
    [self presentViewController:navigationController animated:YES completion:nil];
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
    
    static TTTTimeIntervalFormatter *timeIntervalFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timeIntervalFormatter = [[TTTTimeIntervalFormatter alloc] init];
    });
    
    if (task.completed) {
        cell.detail.text = [NSString stringWithFormat:@"Completed %@", [timeIntervalFormatter stringForTimeInterval:[task.completedAt timeIntervalSinceDate:NSDate.date]]];
    } else {
        cell.detail.text = @"Incomplete";
    }
    
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
    taskEditViewController.dismissBlock = ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
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
