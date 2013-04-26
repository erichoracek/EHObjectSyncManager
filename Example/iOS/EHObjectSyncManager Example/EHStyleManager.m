//
//  EHStyleManager.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/15/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHStyleManager.h"

static EHStyleManager *singletonInstance = nil;

@implementation EHStyleManager

+ (instancetype)sharedManager
{
    if (!singletonInstance) {
        singletonInstance = [[[self class] alloc] init];
    }
    return singletonInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
        [MSTableCell applyDefaultAppearance];
        [MSGroupedTableViewCell applyDefaultAppearance];
        
        [[MSPlainCellBackgroundView appearance] setBackgroundColor:[UIColor whiteColor]];
        
        // Set a gradient background image as the navigation bar image
        CGSize navigationBarSize = CGSizeMake(320.0, 44.0);
        UIGraphicsBeginImageContext(navigationBarSize);
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = (CGRect){CGPointZero, navigationBarSize};
        gradient.colors = @[ (id)[UIColor colorWithHexString:@"444444"].CGColor, (id)[UIColor colorWithHexString:@"000000"].CGColor ];
        [gradient renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *backgroundImage = UIGraphicsGetImageFromCurrentImageContext();
        [[UINavigationBar appearance] setBackgroundImage:backgroundImage forBarMetrics:UIBarMetricsDefault];
        [[UIToolbar appearance] setBackgroundImage:backgroundImage forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
        UIGraphicsEndImageContext();
        
        [MSTableCell.appearance setAccessoryCharacter:@"\U000025BB" forAccessoryType:MSTableCellAccessoryDisclosureIndicator];
        [MSTableCell.appearance setAccessoryCharacter:@"\U00002713" forAccessoryType:MSTableCellAccessoryCheckmark];
        [MSTableCell.appearance setAccessoryCharacter:@"\U000022C6" forAccessoryType:MSTableCellAccessoryStarFull];
        [MSTableCell.appearance setAccessoryCharacter:@"\U0001F6AB" forAccessoryType:MSTableCellAccessoryStarEmpty];

        UIFont *accessoryFont = [self symbolSetFontOfSize:14.0];
        [MSTableCell.appearance setAccessoryTextAttributes:@{ UITextAttributeFont : accessoryFont } forState:UIControlStateNormal];
    }
    return self;
}

- (UIFont *)symbolSetFontOfSize:(CGFloat)size
{
    return [UIFont fontWithName:@"SS Standard" size:size];
}

- (UIBarButtonItem *)styledBarButtonItemWithSymbolsetTitle:(NSString *)title action:(void(^)(void))handler
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [self symbolSetFontOfSize:16.0];
    button.contentEdgeInsets = UIEdgeInsetsMake(5.0, 8.0, 0.0, 8.0);
    button.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [button setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
    [button setTitle:title forState:UIControlStateNormal];
    [button sizeToFit];

    [button addEventHandler:handler forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    return barButtonItem;
}

@end
