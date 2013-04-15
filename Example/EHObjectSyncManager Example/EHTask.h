//
//  EHTask.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface EHTask : NSManagedObject

@property (nonatomic, retain) NSNumber *remoteID;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSDate *dueAt;
@property (nonatomic, retain) NSDate *completedAt;
@property (nonatomic, retain) NSSet *reminders;

// Derived Attributes
@property (nonatomic, strong, readonly) NSString *dueAtString;
@property (nonatomic, strong, readonly) NSString *completedAtString;
@property (nonatomic, assign) BOOL completed;

@end
