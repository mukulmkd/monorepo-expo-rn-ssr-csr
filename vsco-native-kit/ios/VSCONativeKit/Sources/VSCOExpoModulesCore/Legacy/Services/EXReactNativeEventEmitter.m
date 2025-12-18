#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import "Legacy/Services/EXReactNativeEventEmitter.h"
#import "Legacy/Protocols/EXEventEmitter.h"
#import "Legacy/EXExportedModule.h"
#import "Legacy/ModuleRegistry/EXModuleRegistry.h"
#import "Swift.h"

@interface EXReactNativeEventEmitter ()

@property (nonatomic, assign) int listenersCount;
@property (nonatomic, weak) EXModuleRegistry *exModuleRegistry;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *modulesListenersCounts;

@end

@implementation EXReactNativeEventEmitter

RCT_EXPORT_MODULE(EXReactNativeEventEmitter)

- (instancetype)init
{
  if (self = [super init]) {
    _listenersCount = 0;
    _modulesListenersCounts = [NSMutableDictionary dictionary];
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

+ (const NSArray<Protocol *> *)exportedInterfaces
{
  return @[@protocol(EXEventEmitterService)];
}

- (NSArray<NSString *> *)supportedEvents
{
  NSMutableSet<NSString *> *eventsAccumulator = [NSMutableSet set];

  // Backwards compatibility for the new architecture
  if (_appContext && [_appContext respondsToSelector:@selector(getSupportedEvents)]) {
    NSArray<NSString *> *supportedEvents = ((NSArray<NSString *> *(*)(id, SEL))objc_msgSend)(_appContext, @selector(getSupportedEvents));
    [eventsAccumulator addObjectsFromArray:supportedEvents];
  }
  for (EXExportedModule *exportedModule in [_exModuleRegistry getAllExportedModules]) {
    if ([exportedModule conformsToProtocol:@protocol(EXEventEmitter)]) {
      id<EXEventEmitter> eventEmitter = (id<EXEventEmitter>)exportedModule;
      [eventsAccumulator addObjectsFromArray:[eventEmitter supportedEvents]];
    }
  }
  return [eventsAccumulator allObjects];
}

RCT_EXPORT_METHOD(addProxiedListener:(NSString *)moduleName eventName:(NSString *)eventName)
{
  [self addListener:eventName];

  // Backwards compatibility for the new architecture
  if (_appContext && [_appContext respondsToSelector:@selector(hasModule:)]) {
    BOOL hasModule = ((BOOL(*)(id, SEL, NSString *))objc_msgSend)(_appContext, @selector(hasModule:), moduleName);
    if (hasModule) {
      ((void(*)(id, SEL, NSString *, NSInteger))objc_msgSend)(_appContext, @selector(modifyEventListenersCount:count:), moduleName, 1);
      return;
    }
  }

  // Validate module
  EXExportedModule *module = [_exModuleRegistry getExportedModuleForName:moduleName];

  if (RCT_DEBUG && module == nil) {
    EXLogError(@"Module for name `%@` has not been found.", moduleName);
    return;
  } else if (RCT_DEBUG && ![module conformsToProtocol:@protocol(EXEventEmitter)]) {
    EXLogError(@"Module `%@` is not an EXEventEmitter, thus it cannot be subscribed to.", moduleName);
    return;
  }

  // Validate eventEmitter
  id<EXEventEmitter> eventEmitter = (id<EXEventEmitter>)module;

  if (RCT_DEBUG && ![[eventEmitter supportedEvents] containsObject:eventName]) {
    EXLogError(@"`%@` is not a supported event type for %@. Supported events are: `%@`",
               eventName, moduleName, [[eventEmitter supportedEvents] componentsJoinedByString:@"`, `"]);
  }

  // Global observing state
  _listenersCount += 1;
  if (_listenersCount == 1) {
    [self startObserving];
  }

  // Per-module observing state
  int newModuleListenersCount = [self moduleListenersCountFor:moduleName] + 1;
  if (newModuleListenersCount == 1) {
    [eventEmitter startObserving];
  }
  _modulesListenersCounts[moduleName] = [NSNumber numberWithInt:newModuleListenersCount];
}

RCT_EXPORT_METHOD(removeProxiedListeners:(NSString *)moduleName count:(double)count)
{
  [self removeListeners:count];

  // Backwards compatibility for the new architecture
  if (_appContext && [_appContext respondsToSelector:@selector(hasModule:)]) {
    BOOL hasModule = ((BOOL(*)(id, SEL, NSString *))objc_msgSend)(_appContext, @selector(hasModule:), moduleName);
    if (hasModule) {
      NSInteger countInt = (NSInteger)count;
      ((void(*)(id, SEL, NSString *, NSInteger))objc_msgSend)(_appContext, @selector(modifyEventListenersCount:count:), moduleName, -countInt);
      return;
    }
  }

  // Validate module
  EXExportedModule *module = [_exModuleRegistry getExportedModuleForName:moduleName];

  if (RCT_DEBUG && module == nil) {
    EXLogError(@"Module for name `%@` has not been found.", moduleName);
    return;
  } else if (RCT_DEBUG && ![module conformsToProtocol:@protocol(EXEventEmitter)]) {
    EXLogError(@"Module `%@` is not an EXEventEmitter, thus it cannot be subscribed to.", moduleName);
    return;
  }

  id<EXEventEmitter> eventEmitter = (id<EXEventEmitter>)module;

  // Per-module observing state
  int newModuleListenersCount = [self moduleListenersCountFor:moduleName] - count;
  if (newModuleListenersCount == 0) {
    [eventEmitter stopObserving];
  } else if (newModuleListenersCount < 0) {
    EXLogError(@"Attempted to remove more `%@` listeners than added", moduleName);
    newModuleListenersCount = 0;
  }
  _modulesListenersCounts[moduleName] = [NSNumber numberWithInt:newModuleListenersCount];

  // Global observing state
  if (_listenersCount - count < 0) {
    EXLogError(@"Attempted to remove more proxied event emitter listeners than added");
    _listenersCount = 0;
  } else {
    _listenersCount -= count;
  }

  if (_listenersCount == 0) {
    [self stopObserving];
  }
}

# pragma mark Utilities

- (int)moduleListenersCountFor:(NSString *)moduleName
{
  NSNumber *moduleListenersCountNumber = _modulesListenersCounts[moduleName];
  int moduleListenersCount = 0;
  if (moduleListenersCountNumber != nil) {
    moduleListenersCount = [moduleListenersCountNumber intValue];
  }
  return moduleListenersCount;
}

# pragma mark - EXModuleRegistryConsumer

- (void)setModuleRegistry:(EXModuleRegistry *)moduleRegistry
{
  // We need to check if we get an object of the correct class because RN 65 tries to call this method with RTCModuleRegistry.
  // See https://github.com/facebook/react-native/blob/2c2b83171603b47e5eec61eea55139f760dba090/React/Base/RCTModuleData.mm#L274-L289.
  if ([moduleRegistry isKindOfClass:[EXModuleRegistry class]]) {
    _exModuleRegistry = moduleRegistry;
  }
}

@end
