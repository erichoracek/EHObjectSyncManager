//
//  EHStyleManager.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/15/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EHStyleManager : NSObject

+ (instancetype)sharedManager;

- (UIBarButtonItem *)styledBarButtonItemWithSymbolsetTitle:(NSString *)title action:(BKSenderBlock)handler;

@end
