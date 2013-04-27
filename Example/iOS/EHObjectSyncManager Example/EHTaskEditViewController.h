//
//  EHTaskEditViewController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/3/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EHManagedObjectEditViewController.h"

@interface EHTaskEditViewController : EHManagedObjectEditViewController

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) void(^dismissBlock)(BOOL animated);

@end
