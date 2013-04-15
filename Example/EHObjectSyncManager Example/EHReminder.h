//
//  EHReminder.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class EHTask;

@interface EHReminder : NSManagedObject

@property (nonatomic, retain) NSNumber *remoteID;
@property (nonatomic, retain) NSDate *remindAt;
@property (nonatomic, retain) EHTask *task;

// Derived Attributes
@property (nonatomic, strong, readonly) NSString *remindAtString;
@property (nonatomic, assign, readonly) BOOL fired;

@end
