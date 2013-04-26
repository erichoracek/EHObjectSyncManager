//
//  EHReminderEditViewController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/13/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHManagedObjectEditViewController.h"

@class EHTask;

@interface EHReminderEditViewController : EHManagedObjectEditViewController

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) void(^dismissBlock)();
@property (nonatomic, strong) EHTask *task;

@end
