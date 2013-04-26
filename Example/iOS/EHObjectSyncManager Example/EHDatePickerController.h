//
//  EHDatePickerController.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/14/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, EHDatePickerControllerCompletionType) {
    EHDatePickerControllerCompletionTypeSave,
    EHDatePickerControllerCompletionTypeClear
};

typedef void (^EHDateChangedBlock)(NSDate *date);
typedef void (^EHDatePickerControllerCompletionBlock)(EHDatePickerControllerCompletionType completionType);

@interface EHDatePickerController : NSObject

@property (nonatomic, strong, readonly) UITextField *hiddenTextField;
@property (nonatomic, strong, readonly) UIDatePicker *datePicker;
@property (nonatomic, strong, readonly) UIToolbar *accessoryToolbar;

@property (nonatomic, strong) EHDateChangedBlock dateChangedBlock;
@property (nonatomic, strong) EHDatePickerControllerCompletionBlock completionBlock;

@end
