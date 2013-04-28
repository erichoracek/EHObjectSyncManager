//
//  EHObjectSyncManager.h
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/2/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <RestKit/RestKit.h>

@class EHSyncDescriptor;

@interface EHObjectSyncManager : RKObjectManager

@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;

- (void)configureSyncManagerWithManagedObjectStore:(RKManagedObjectStore *)managedObjectStore;

/**
 Returns an array containing the `RKSyncDescriptor` objects added to the manager.
 
 @return An array containing the sync descriptors of the receiver. The elements of the array are instances of `RKSyncDescriptor`.
 
 @see EHSyncDescriptor
 */
@property (nonatomic, readonly) NSArray *syncDescriptors;

/**
 Adds a sync descriptor to the manager.
 
 Adding a sync descriptor to the manager sets the `baseURL` of the descriptor to the `baseURL` of the manager, causing it to evaluate URL objects relatively.
 
 @param syncDescriptor The sync descriptor object to the be added to the manager.
 */
- (void)addSyncDescriptor:(EHSyncDescriptor *)syncDescriptor;

/**
 Adds the `EHSyncDescriptor` objects contained in a given array to the manager.
 
 @param syncDescriptors An array of `EHSyncDescriptor` objects to be added to the manager.
 @exception NSInvalidArgumentException Raised if any element of the given array is not an `EHSyncDescriptor` object.
 */
- (void)addSyncDescriptorsFromArray:(NSArray *)syncDescriptors;

/**
 Removes a given sync descriptor from the manager.
 
 @param syncDescriptor An `EHSyncDescriptor` object to be removed from the manager.
 */
- (void)removeSyncDescriptor:(EHSyncDescriptor *)syncDescriptor;

@end

typedef BOOL (^EHSyncDescriptorExistsRemotelyBlock)(NSManagedObject *managedObject);

@interface EHSyncDescriptor : NSObject

@property (nonatomic, strong, readonly) RKEntityMapping *entityMapping;
@property (nonatomic, copy, readonly) NSNumber *syncRank;
@property (nonatomic, strong, readonly) EHSyncDescriptorExistsRemotelyBlock existsRemotelyBlock;

+ (instancetype)syncDescriptorWithMapping:(RKEntityMapping *)mapping
                                 syncRank:(NSNumber *)syncRank
                      existsRemotelyBlock:(EHSyncDescriptorExistsRemotelyBlock)existsRemotelyBlock;

@end

@interface EHObjectSyncOperation : NSOperation

@property (nonatomic, strong) NSString *objectIDStringURI;
@property (nonatomic, assign) RKRequestMethod syncRequestMethod;
@property (nonatomic, strong) Class syncClass;
@property (nonatomic, strong) NSDate *syncDate;
@property (nonatomic, strong) NSNumber *syncRank;

@property (nonatomic, weak) EHObjectSyncManager *objectSyncManager;
@property (nonatomic, strong) NSManagedObject *syncObject;
@property (nonatomic, strong) NSString *syncPath;

@property (nonatomic, strong, readonly) NSOperation *syncRequestOperation;

@end
