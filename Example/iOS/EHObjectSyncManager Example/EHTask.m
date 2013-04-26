//
//  EHTask.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHTask.h"
#import "EHReminder.h"
#import "EHManagedObjectEditViewController.h"

@implementation EHTask

@dynamic name;
@dynamic dueAt;
@dynamic completedAt;
@dynamic reminders;
@dynamic completed;
@dynamic remoteID;

#pragma mark - NSManagedObject

- (BOOL)validateName:(id *)name error:(NSError *__autoreleasing *)error
{
    // If our context is an EHManagedObjectEditViewController private context, only run validations on the edited object
    if (EHManagedObjectEditViewControllerIsEditingOtherObject(self)) {
        return YES;
    }
    if ((*name == nil) || [*name isEqualToString:@""]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"" code:1024 userInfo:@{ NSLocalizedDescriptionKey : @"A task requires a name" }];
        }
        return NO;
    }
    return YES;
}

#pragma mark - EHTask

- (void)setCompleted:(BOOL)completed
{
    NSDate *completedAt = (completed ? [NSDate date] : nil);
    self.completedAt = completedAt;
}

- (BOOL)completed
{
    return (self.completedAt != nil);
}

- (NSString *)dueAtString
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"EEE MMM d, h:mm a";
    });
    return (self.dueAt ? [dateFormatter stringFromDate:self.dueAt] : nil);
}

- (NSString *)completedAtString
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"EEE MMM d, h:mm a";
    });
    return (self.completedAt ? [dateFormatter stringFromDate:self.completedAt] : nil);
}

@end
