//
//  EHDatePickerController.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/14/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHDatePickerController.h"
#import "EHStyleManager.h"
#import "IXPickerOverlayView.h"

@interface EHDatePickerController () <UITextFieldDelegate>

@property (nonatomic, strong, readwrite) UITextField *hiddenTextField;
@property (nonatomic, strong, readwrite) UIDatePicker *datePicker;
@property (nonatomic, strong, readwrite) UIToolbar *accessoryToolbar;
@property (nonatomic, strong) IXPickerOverlayView *pickerOverlayView;

- (void)clear;
- (void)save;

@end

@implementation EHDatePickerController

- (id)init
{
    self = [super init];
    if (self) {
        self.accessoryToolbar = [UIToolbar new];
        self.accessoryToolbar.tintColor = [UIColor blackColor];
        
        __weak typeof (self) weakSelf = self;
        UIBarButtonItem* clearBarButtonItem = [[EHStyleManager sharedManager] styledBarButtonItemWithSymbolsetTitle:@"\U00002421" action:^(id sender) {
            [weakSelf clear];
        }];
        UIBarButtonItem *saveBarButtonItem = [[EHStyleManager sharedManager] styledBarButtonItemWithSymbolsetTitle:@"\U00002713" action:^(id sender) {
            [weakSelf save];
        }];
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        self.accessoryToolbar.items = @[ clearBarButtonItem, flex, saveBarButtonItem ];
        [self.accessoryToolbar sizeToFit];
        
        self.hiddenTextField = [[UITextField alloc] init];
        self.hiddenTextField.delegate = self;
        _hiddenTextField.hidden = YES;
        
        self.datePicker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
        [self.datePicker addTarget:self action:@selector(dateChangedForDueDatePicker:) forControlEvents:UIControlEventValueChanged];
        self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
        
        self.pickerOverlayView = [IXPickerOverlayView new];
        [self.datePicker addSubview:self.pickerOverlayView];
        
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

- (void)clear;
{
    if (self.completionBlock) self.completionBlock(EHDatePickerControllerCompletionTypeClear);
}

- (void)save;
{
    if (self.completionBlock) self.completionBlock(EHDatePickerControllerCompletionTypeSave);
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    [self.pickerOverlayView setNeedsLayout];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if (self.dateChangedBlock) self.dateChangedBlock(self.datePicker.date);
    [self.datePicker.superview addSubview:self.pickerOverlayView];
    self.pickerOverlayView.frame = self.datePicker.frame;
}

@end
