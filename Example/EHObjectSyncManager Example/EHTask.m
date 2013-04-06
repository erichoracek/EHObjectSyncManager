//
//  EHTask.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHTask.h"
#import "EHReminder.h"


@implementation EHTask

@dynamic name;
@dynamic dueAt;
@dynamic completedAt;
@dynamic reminders;
@dynamic completed;
@dynamic remoteID;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    self.remoteID = nil;
}

- (BOOL)validateName:(id *)name error:(NSError *__autoreleasing *)error
{
    if ((*name == nil) || [*name isEqualToString:@""]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"" code:1024 userInfo:@{ NSLocalizedDescriptionKey : @"A task requires a name"}];
        }
        return NO;
    }
    return YES;
}

- (void)setCompleted:(BOOL)completed
{
    NSDate *completedAt = (completed ? [NSDate date] : nil);
    self.completedAt = completedAt;
}

- (BOOL)completed
{
    return (self.completedAt != nil);
}

@end
