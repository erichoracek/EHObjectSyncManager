//
//  EHTasksViewController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface EHTasksViewController : UICollectionViewController

@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;

@end
