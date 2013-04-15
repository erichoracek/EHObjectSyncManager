//
//  EHReminder.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHReminder.h"
#import "EHTask.h"

@implementation EHReminder

@dynamic remoteID;
@dynamic remindAt;
@dynamic task;

#pragma mark - NSManagedObject

- (BOOL)validateRemindAt:(id *)remindAt error:(NSError *__autoreleasing *)error
{
    if (*remindAt == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"" code:1024 userInfo:@{ NSLocalizedDescriptionKey : @"A reminder requires a time to remind at." }];
        }
        return NO;
    }
    return YES;
}

#pragma mark - EHReminder

- (NSString *)remindAtString
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"EEE, MMM d 'at' h:mm a";
    });
    return (self.remindAt ? [dateFormatter stringFromDate:self.remindAt] : @"None");
}

- (BOOL)fired
{
    return ([self.remindAt compare:[NSDate date]] == NSOrderedDescending);
}

@end
