//
//  EHAppDelegate.m
//  EHObjectSyncManager Example
//
//  Created by Eric Horacek on 4/1/13.
//  Copyright (c) 2013 Eric Horacek. All rights reserved.
//

#import "EHAppDelegate.h"
#import "EHTasksViewController.h"
#import "EHObjectSyncManager.h"
#import "EHTask.h"

@interface EHAppDelegate ()

- (void)setupRestKitWithBaseURL:(NSURL *)baseURL;
- (void)setupPonyDebugger;

@end

@implementation EHAppDelegate

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
//    [self setupRestKitWithBaseURL:[NSURL URLWithString:@"http://ehobjectsyncmanager.herokuapp.com"]];
    [self setupRestKitWithBaseURL:[NSURL URLWithString:@"http://ehobjectsyncmanager.10.0.1.5.xip.io"]];
    [self setupPonyDebugger];
    
    [MSTableCell applyDefaultAppearance];
    [MSGroupedTableViewCell applyDefaultAppearance];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    EHTasksViewController *tasksController = [[EHTasksViewController alloc] init];
    tasksController.managedObjectContext = [[EHObjectSyncManager sharedManager] managedObjectContext];
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:tasksController];
    self.window.rootViewController = navigationController;
    
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

#pragma mark - EHAppDelegate

- (void)setupRestKitWithBaseURL:(NSURL *)baseURL
{
    EHObjectSyncManager *objectManager = [EHObjectSyncManager managerWithBaseURL:baseURL];
    
    [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;

    // Initialize managed object store
    NSManagedObjectModel *managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];
    RKManagedObjectStore *managedObjectStore = [[RKManagedObjectStore alloc] initWithManagedObjectModel:managedObjectModel];
    objectManager.managedObjectStore = managedObjectStore;
    
    RKEntityMapping *taskResponseMapping = [RKEntityMapping mappingForEntityForName:@"Task" inManagedObjectStore:managedObjectStore];
    taskResponseMapping.identificationAttributes = @[ @"remoteID" ];
    [taskResponseMapping addAttributeMappingsFromDictionary:@{ @"id" : @"remoteID", @"completed_at" : @"completedAt", @"due_at" : @"dueAt"}];
    [taskResponseMapping addAttributeMappingsFromArray:@[ @"name" ]];
    
    RKEntityMapping *reminderResponseMapping = [RKEntityMapping mappingForEntityForName:@"Reminder" inManagedObjectStore:managedObjectStore];
    reminderResponseMapping.identificationAttributes = @[ @"remoteID" ];
    [reminderResponseMapping addAttributeMappingsFromDictionary:@{ @"id" : @"remoteID", @"task_id" : @"taskID", @"remind_at" : @"remindAt" }];
    
    // Task <->> Reminder
    [reminderResponseMapping addConnectionForRelationship:@"task" connectedBy:@{@"taskID" : @"remoteID"}];
    
    RKResponseDescriptor *taskIndexResponseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskResponseMapping pathPattern:@"/tasks.json" keyPath:@"task" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:taskIndexResponseDescriptor];
    
    RKResponseDescriptor *taskPutResponseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:taskResponseMapping pathPattern:@"/tasks/:remoteID\\.json" keyPath:@"task" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:taskPutResponseDescriptor];
    
    RKObjectMapping* taskRequestMapping = [RKObjectMapping requestMapping];
    [taskRequestMapping addAttributeMappingsFromArray:@[ @"name" ]];
    [taskRequestMapping addAttributeMappingsFromDictionary:@{ @"completedAt" : @"completed_at", @"dueAt" : @"due_at" }];
    taskRequestMapping.setDefaultValueForMissingAttributes = YES;
    
    RKRequestDescriptor *taskRequestDescriptor = [RKRequestDescriptor requestDescriptorWithMapping:taskRequestMapping objectClass:EHTask.class rootKeyPath:@"task"];
    [objectManager addRequestDescriptor:taskRequestDescriptor];
    
    [objectManager.router.routeSet addRoute:[RKRoute routeWithClass:EHTask.class pathPattern:@"/tasks/:remoteID\\.json" method:RKRequestMethodGET]];
    [objectManager.router.routeSet addRoute:[RKRoute routeWithClass:EHTask.class pathPattern:@"/tasks/:remoteID\\.json" method:RKRequestMethodPUT]];
    [objectManager.router.routeSet addRoute:[RKRoute routeWithClass:EHTask.class pathPattern:@"/tasks/:remoteID\\.json" method:RKRequestMethodDELETE]];
    [objectManager.router.routeSet addRoute:[RKRoute routeWithClass:EHTask.class pathPattern:@"/tasks.json" method:RKRequestMethodPOST]];
    
    RKResponseDescriptor *reminderIndexResponseDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:reminderResponseMapping pathPattern:@"/reminders.json" keyPath:@"reminder" statusCodes:RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful)];
    [objectManager addResponseDescriptor:reminderIndexResponseDescriptor];
    
    [objectManager addFetchRequestBlock:^NSFetchRequest *(NSURL *URL) {
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:@"/tasks.json"];
        NSDictionary *argsDict = nil;
        BOOL match = [pathMatcher matchesPath:[URL relativePath] tokenizeQueryStrings:NO parsedArguments:&argsDict];
        if (match) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Task"];
            fetchRequest.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"completedAt" ascending:YES] ];
            return fetchRequest;
        }
        return nil;
    }];
    
    [objectManager addFetchRequestBlock:^NSFetchRequest *(NSURL *URL) {
        RKPathMatcher *pathMatcher = [RKPathMatcher pathMatcherWithPattern:@"/reminders.json"];
        NSDictionary *argsDict = nil;
        BOOL match = [pathMatcher matchesPath:[URL relativePath] tokenizeQueryStrings:NO parsedArguments:&argsDict];
        if (match) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Reminder"];
            fetchRequest.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"remindAt" ascending:YES] ];
            return fetchRequest;
        }
        return nil;
    }];
    
    [objectManager addSyncDescriptor:[EHSyncDescriptor syncDescriptorWithMapping:taskResponseMapping syncRank:@1 existsRemotelyBlock:^BOOL(id task) {
        if ([task valueForKey:@"remoteID"]) {
            return YES;
        }
        return NO;
    }]];
    
    [managedObjectStore createPersistentStoreCoordinator];
    NSString *storePath = [RKApplicationDataDirectory() stringByAppendingPathComponent:@"Store.sqlite"];
    NSError *error;
    NSPersistentStore *persistentStore = [managedObjectStore addSQLitePersistentStoreAtPath:storePath fromSeedDatabaseAtPath:nil withConfiguration:nil options:nil error:&error];
    NSAssert(persistentStore, @"Failed to add persistent store with error: %@", error);
    [managedObjectStore createManagedObjectContexts];
    
    [objectManager configureSyncManagerWithManagedObjectStore:managedObjectStore];
    
    managedObjectStore.managedObjectCache = [[RKFetchRequestManagedObjectCache alloc] init];
    
//    RKLogConfigureByName("RestKit/ObjectMapping", RKLogLevelTrace);
//    RKLogConfigureByName("RestKit/CoreData", RKLogLevelTrace);
//    RKLogConfigureByName("RestKit/Network", RKLogLevelTrace);
//    RKLogConfigureByName("RestKit", RKLogLevelTrace);
}

- (void)setupPonyDebugger
{
    PDDebugger *debugger = [PDDebugger defaultInstance];
    [debugger connectToURL:[NSURL URLWithString:@"ws://localhost:9000/device"]];
//    [debugger autoConnect];
    
    [debugger enableNetworkTrafficDebugging];
    [debugger forwardAllNetworkTraffic];
    
    [debugger enableCoreDataDebugging];
    [debugger addManagedObjectContext:[[RKManagedObjectStore defaultStore] persistentStoreManagedObjectContext] withName:@"RestKit Persistent Store"];
    [debugger addManagedObjectContext:[[RKManagedObjectStore defaultStore] mainQueueManagedObjectContext] withName:@"Main Queue Persistent Store"];
//    [debugger addManagedObjectContext:[[EHObjectSyncManager sharedManager] managedObjectContext] withName:@"Object Sync Manager Context"];
}

@end
