//
//  EHDatePickerController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/14/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHDatePickerController.h"

@interface EHDatePickerController ()

@property (nonatomic, strong, readwrite) UITextField *hiddenTextField;
@property (nonatomic, strong, readwrite) UIDatePicker *datePicker;
@property (nonatomic, strong, readwrite) UIToolbar *accessoryToolbar;

@end

@implementation EHDatePickerController

- (id)init
{
    self = [super init];
    if (self) {
        self.accessoryToolbar = [UIToolbar new];
        self.accessoryToolbar.tintColor = [UIColor blackColor];
        UIBarButtonItem* clearBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStyleBordered target:self action:@selector(accessoryToolbarClearButtonTapped:)];
        UIBarButtonItem* saveBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleBordered target:self action:@selector(accessoryToolbarSaveButtonTapped:)];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.accessoryToolbar.items = @[ clearBarButtonItem, flex, saveBarButtonItem ];
        [self.accessoryToolbar sizeToFit];
        
        self.hiddenTextField = [[UITextField alloc] init];
        self.hiddenTextField.delegate = self;
        _hiddenTextField.hidden = YES;
        
        self.datePicker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
        [self.datePicker addTarget:self action:@selector(dateChangedForDueDatePicker:) forControlEvents:UIControlEventValueChanged];
        self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
        
        self.hiddenTextField.inputView = self.datePicker;
        self.hiddenTextField.inputAccessoryView = self.accessoryToolbar;
    }
    return self;
}

#pragma mark - EHDatePickerController

- (void)dateChangedForDueDatePicker:(id)sender
{
    if (self.dateChangedBlock) self.dateChangedBlock(self.datePicker.date);
}

- (void)accessoryToolbarClearButtonTapped:(id)sender
{
    if (self.completionBlock) self.completionBlock(EHDatePickerControllerCompletionTypeClear);
}

- (void)accessoryToolbarSaveButtonTapped:(id)sender
{
    if (self.completionBlock) self.completionBlock(EHDatePickerControllerCompletionTypeSave);
}

@end
