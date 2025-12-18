#import <Foundation/Foundation.h>
// Copyright 2018-present 650 Industries. All rights reserved.

#import <objc/runtime.h>

@class RCTBridge;
@class RCTModuleData;

#if __has_include(<React/RCTComponentViewFactory.h>)
#import <React/RCTComponentViewFactory.h> // Allows non-umbrella since it's coming from React-RCTFabric
#endif
#import <React/RCTUIManager.h>
#import <React/RCTComponentData.h>
#import <React/RCTViewManager.h>

#include <jsi/jsi.h>

#import "Legacy/NativeModulesProxy/EXNativeModulesProxy.h"
#import "Legacy/Protocols/EXEventEmitter.h"
#import "Legacy/ModuleRegistryProvider/EXModuleRegistryProvider.h"
#import "Legacy/Services/EXReactNativeEventEmitter.h"
#import "JSI/EXJSIInstaller.h"
#import "Core/ExpoBridgeModule.h"
#import <objc/message.h>

static const NSString *exportedMethodsNamesKeyPath = @"exportedMethods";
static const NSString *viewManagersMetadataKeyPath = @"viewManagersMetadata";
static const NSString *exportedConstantsKeyPath = @"modulesConstants";

static const NSString *methodInfoKeyKey = @"key";
static const NSString *methodInfoNameKey = @"name";
static const NSString *methodInfoArgumentsCountKey = @"argumentsCount";

@interface EXModulesProxyConfig ()

@property (readonly) NSMutableDictionary *exportedConstants;
@property (readonly) NSMutableDictionary *methodNames;
@property (readonly) NSMutableDictionary *viewManagerMetadata;

@end

@implementation EXModulesProxyConfig

- (instancetype)initWithConstants:(nonnull NSDictionary *)constants
                      methodNames:(nonnull NSDictionary *)methodNames
                     viewManagers:(nonnull NSDictionary *)viewManagerMetadata
{
  if (self = [super init]) {
    _exportedConstants = constants;
    _methodNames = methodNames;
    _viewManagerMetadata = viewManagerMetadata;
  }
  return self;
}

- (void)addEntriesFromConfig:(nonnull const EXModulesProxyConfig*)config
{
  [_exportedConstants addEntriesFromDictionary:config.exportedConstants];
  [_methodNames addEntriesFromDictionary:config.methodNames];
  [_viewManagerMetadata addEntriesFromDictionary:config.viewManagerMetadata];
}

- (nonnull NSDictionary<NSString *, id> *)toDictionary
{
  NSMutableDictionary <NSString *, id> *constantsAccumulator = [NSMutableDictionary dictionary];
  constantsAccumulator[viewManagersMetadataKeyPath] = _viewManagerMetadata;
  constantsAccumulator[exportedConstantsKeyPath] = _exportedConstants;
  constantsAccumulator[exportedMethodsNamesKeyPath] = _methodNames;
  return constantsAccumulator;
}

@end

@interface RCTBridge (RegisterAdditionalModuleClasses)

- (NSArray<RCTModuleData *> *)registerModulesForClasses:(NSArray<Class> *)moduleClasses;
- (void)registerAdditionalModuleClasses:(NSArray<Class> *)modules;

@end

@interface RCTBridge (JSIRuntime)

- (void *)runtime;

@end

@interface EXNativeModulesProxy ()

@property (nonatomic, strong) NSRegularExpression *regexp;
@property (nonatomic, strong) EXModuleRegistry *exModuleRegistry;
@property (nonatomic, strong) NSMutableDictionary<const NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *exportedMethodsKeys;
@property (nonatomic, strong) NSMutableDictionary<const NSString *, NSMutableDictionary<NSNumber *, NSString *> *> *exportedMethodsReverseKeys;
@property (nonatomic) BOOL ownsModuleRegistry;

@end

@implementation EXNativeModulesProxy {
  __weak id _Nullable _appContext;  // Use id instead of EXAppContext (Swift class)
}

@synthesize bridge = _bridge;
@synthesize nativeModulesConfig = _nativeModulesConfig;

RCT_EXPORT_MODULE(NativeUnimoduleProxy)

/**
 The designated initializer. It's used in the old setup where the native modules proxy
 is registered in `extraModulesForBridge:` by the bridge delegate.
 */
- (instancetype)initWithModuleRegistry:(nullable EXModuleRegistry *)moduleRegistry
{
  if (self = [super init]) {
    _exModuleRegistry = moduleRegistry != nil ? moduleRegistry : [[EXModuleRegistryProvider new] moduleRegistry];
    _exportedMethodsKeys = [NSMutableDictionary dictionary];
    _exportedMethodsReverseKeys = [NSMutableDictionary dictionary];
    _ownsModuleRegistry = moduleRegistry == nil;
  }
  return self;
}

/**
 The initializer for Expo Go to pass a custom `EXModuleRegistry`
 other than the default one from `EXModuleRegistryProvider`.
 The `EXModuleRegistry` is still owned by this class.
 */
- (instancetype)initWithCustomModuleRegistry:(nonnull EXModuleRegistry *)moduleRegistry
{
  self = [self initWithModuleRegistry:moduleRegistry];
  self.ownsModuleRegistry = YES;
  return self;
}

/**
 Convenience initializer used by React Native in the new setup, where the modules are registered automatically.
 */
- (instancetype)init
{
  return [self initWithModuleRegistry:nil];
}

# pragma mark - React API

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (nonnull EXModulesProxyConfig *)nativeModulesConfig
{
  if (_nativeModulesConfig) {
    return _nativeModulesConfig;
  }

  NSMutableDictionary <NSString *, id> *exportedModulesConstants = [NSMutableDictionary dictionary];
  // Grab all the constants exported by modules
  for (EXExportedModule *exportedModule in [_exModuleRegistry getAllExportedModules]) {
    @try {
      exportedModulesConstants[[[exportedModule class] exportedModuleName]] = [exportedModule constantsToExport] ?: [NSNull null];
    } @catch (NSException *exception) {
      continue;
    }
  }

  // Also add `exportedMethodsNames`
  NSMutableDictionary<const NSString *, NSMutableArray<NSMutableDictionary<const NSString *, id> *> *> *exportedMethodsNamesAccumulator = [NSMutableDictionary dictionary];
  for (EXExportedModule *exportedModule in [_exModuleRegistry getAllExportedModules]) {
    const NSString *exportedModuleName = [[exportedModule class] exportedModuleName];
    exportedMethodsNamesAccumulator[exportedModuleName] = [NSMutableArray array];
    [[exportedModule getExportedMethods] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull exportedName, NSString * _Nonnull selectorName, BOOL * _Nonnull stop) {
      NSMutableDictionary<const NSString *, id> *methodInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                                              methodInfoNameKey: exportedName,
                                                                                                              // - 3 is for resolver and rejecter of the promise and the last, empty component
                                                                                                              methodInfoArgumentsCountKey: @([[selectorName componentsSeparatedByString:@":"] count] - 3)
                                                                                                              }];
      [exportedMethodsNamesAccumulator[exportedModuleName] addObject:methodInfo];
    }];
    [self assignExportedMethodsKeys:exportedMethodsNamesAccumulator[exportedModuleName] forModuleName:exportedModuleName];
  }

  EXModulesProxyConfig *config = [[EXModulesProxyConfig alloc] initWithConstants:exportedModulesConstants
                                                                     methodNames:exportedMethodsNamesAccumulator
                                                                    viewManagers:[NSMutableDictionary new]];
  // decorate legacy config with sweet expo-modules config
  // Call expoModulesConfig dynamically
  if (_appContext && [_appContext respondsToSelector:@selector(expoModulesConfig)]) {
    id expoConfig = ((id(*)(id, SEL))objc_msgSend)(_appContext, @selector(expoModulesConfig));
    if (expoConfig) {
      // Cast to EXModulesProxyConfig - expoConfig is returned as id but is actually EXModulesProxyConfig
      EXModulesProxyConfig *expoConfigTyped = (EXModulesProxyConfig *)expoConfig;
      [config addEntriesFromConfig:expoConfigTyped];
    }
  }

  _nativeModulesConfig = config;
  return config;
}

- (nonnull NSDictionary *)constantsToExport
{
  return [self.nativeModulesConfig toDictionary];
}

- (void)setBridge:(RCTBridge *)bridge
{
  ExpoBridgeModule *expoBridgeModule = [bridge moduleForClass:ExpoBridgeModule.class];
  [expoBridgeModule legacyProxyDidSetBridge:self legacyModuleRegistry:_exModuleRegistry];

  // Get appContext property dynamically
  if (expoBridgeModule && [expoBridgeModule respondsToSelector:@selector(appContext)]) {
    _appContext = ((id(*)(id, SEL))objc_msgSend)(expoBridgeModule, @selector(appContext));
  }

  if (!_bridge) {
    // The `setBridge` can be called during module setup or after. Registering more modules
    // during setup causes a crash due to mutating `_moduleDataByID` while it's being enumerated.
    // In that case we register them asynchronously.
    if ([[bridge valueForKey:@"_moduleSetupComplete"] boolValue]) {
      [self registerExpoModulesInBridge:bridge];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self registerExpoModulesInBridge:bridge];
      });
    }
  }
  _bridge = bridge;
}

RCT_EXPORT_METHOD(callMethod:(NSString *)moduleName methodNameOrKey:(id)methodNameOrKey arguments:(NSArray *)arguments resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
  // Backwards compatibility for the new architecture
  // Call hasModule: dynamically
  BOOL hasModule = NO;
  if (_appContext && [_appContext respondsToSelector:@selector(hasModule:)]) {
    hasModule = ((BOOL(*)(id, SEL, NSString *))objc_msgSend)(_appContext, @selector(hasModule:), moduleName);
  }
  
  if (hasModule) {
    // Call callFunction:onModule:withArgs:resolve:reject: dynamically
    if ([_appContext respondsToSelector:@selector(callFunction:onModule:withArgs:resolve:reject:)]) {
      ((void(*)(id, SEL, id, NSString *, NSArray *, RCTPromiseResolveBlock, RCTPromiseRejectBlock))objc_msgSend)(
        _appContext,
        @selector(callFunction:onModule:withArgs:resolve:reject:),
        methodNameOrKey,
        moduleName,
        arguments,
        resolve,
        reject
      );
    }
    return;
  }

  EXExportedModule *module = [_exModuleRegistry getExportedModuleForName:moduleName];
  if (module == nil) {
    NSString *reason = [NSString stringWithFormat:@"No exported module was found for name '%@'. Are you sure all the packages are linked correctly?", moduleName];
    reject(@"E_NO_MODULE", reason, nil);
    return;
  }

  if (!methodNameOrKey) {
    reject(@"E_NO_METHOD", @"No method key or name provided", nil);
    return;
  }

  NSString *methodName;
  if ([methodNameOrKey isKindOfClass:[NSString class]]) {
    methodName = (NSString *)methodNameOrKey;
  } else if ([methodNameOrKey isKindOfClass:[NSNumber class]]) {
    methodName = _exportedMethodsReverseKeys[moduleName][(NSNumber *)methodNameOrKey];
  } else {
    reject(@"E_INV_MKEY", @"Method key is neither a String nor an Integer -- don't know how to map it to method name.", nil);
    return;
  }

  dispatch_async([module methodQueue], ^{
    @try {
      [module callExportedMethod:methodName withArguments:arguments resolver:resolve rejecter:reject];
    } @catch (NSException *e) {
      NSString *message = [NSString stringWithFormat:@"An exception was thrown while calling `%@.%@` with arguments `%@`: %@", moduleName, methodName, arguments, e];
      reject(@"E_EXC", message, nil);
    }
  });
}

#pragma mark - Privates

- (void)registerExpoModulesInBridge:(RCTBridge *)bridge
{
  // Registering expo modules (excluding Swifty view managers!) in bridge is needed only when the proxy module owns
  // the registry (was autoinitialized by React Native). Otherwise they're registered by the registry adapter.
  BOOL ownsModuleRegistry = _ownsModuleRegistry && ![bridge moduleIsInitialized:[EXReactNativeEventEmitter class]];

  // An array of `RCTBridgeModule` classes to register.
  NSMutableArray<Class<RCTBridgeModule>> *additionalModuleClasses = [NSMutableArray new];
  NSMutableSet *visitedSweetModules = [NSMutableSet new];

  // Add dynamic wrappers for view modules written in Sweet API.
  // Call getViewManagers dynamically
  NSArray *viewManagers = nil;
  if (_appContext && [_appContext respondsToSelector:@selector(getViewManagers)]) {
    viewManagers = ((NSArray *(*)(id, SEL))objc_msgSend)(_appContext, @selector(getViewManagers));
  }
  
  if (viewManagers) {
    for (id swiftViewModule in viewManagers) {
      // Get appIdentifier dynamically
      NSString *appId = nil;
      if (_appContext && [_appContext respondsToSelector:@selector(appIdentifier)]) {
        appId = ((NSString *(*)(id, SEL))objc_msgSend)(_appContext, @selector(appIdentifier));
      }
      
      Class wrappedViewModuleClass = [self registerComponentData:swiftViewModule
                                                        inBridge:bridge
                                                        forAppId:appId];
      [additionalModuleClasses addObject:wrappedViewModuleClass];
      
      // Get name property dynamically
      NSString *moduleName = nil;
      if ([swiftViewModule respondsToSelector:@selector(name)]) {
        moduleName = ((NSString *(*)(id, SEL))objc_msgSend)(swiftViewModule, @selector(name));
      }
      if (moduleName) {
        [visitedSweetModules addObject:moduleName];
      }
    }
  }

  // Get ViewModuleWrapper class dynamically
  Class viewModuleWrapperClass = NSClassFromString(@"ViewModuleWrapper");
  if (viewModuleWrapperClass) {
    [additionalModuleClasses addObject:viewModuleWrapperClass];
    [self registerLegacyComponentData:viewModuleWrapperClass inBridge:bridge];
  }

  // Add modules from legacy module registry only when the NativeModulesProxy owns the registry.
  if (ownsModuleRegistry) {
    // Some modules might need access to the bridge.
    for (id module in [_exModuleRegistry getAllInternalModules]) {
      if ([module conformsToProtocol:@protocol(RCTBridgeModule)]) {
        [module setValue:bridge forKey:@"bridge"];
      }
    }
  }

  // `registerAdditionalModuleClasses:` call below is not thread-safe if RCTUIManager is not initialized.
  // The case happens especially with reanimated which accesses `bridge.uiManager` and initialize bridge in js thread.
  // Accessing uiManager here, we try to make sure RCTUIManager is initialized.
  [bridge uiManager];

  // Register the view managers as additional modules.
  [self registerAdditionalModuleClasses:additionalModuleClasses inBridge:bridge];

  // Get the instance of `EXReactEventEmitter` bridge module and give it access to the interop bridge.
  EXReactNativeEventEmitter *eventEmitter = [bridge moduleForClass:[EXReactNativeEventEmitter class]];
  // Set appContext property dynamically
  if (eventEmitter && [eventEmitter respondsToSelector:@selector(setAppContext:)]) {
    ((void(*)(id, SEL, id))objc_msgSend)(eventEmitter, @selector(setAppContext:), _appContext);
  }

  // As the last step, when the registry is owned,
  // register the event emitter and initialize the registry.
  if (ownsModuleRegistry) {
    [_exModuleRegistry registerInternalModule:eventEmitter];

    // Let the modules consume the registry :)
    // It calls `setModuleRegistry:` on all `EXModuleRegistryConsumer`s.
    [_exModuleRegistry initialize];
  }
}

- (void)registerAdditionalModuleClasses:(NSArray<Class> *)moduleClasses inBridge:(RCTBridge *)bridge
{
  // In remote debugging mode, i.e. executorClass is `RCTWebSocketExecutor`,
  // there is a deadlock issue in `registerAdditionalModuleClasses:` and causes app freezed.
  //   - The JS thread acquired the `RCTCxxBridge._moduleRegistryLock` lock in `RCTCxxBridge._initializeBridgeLocked`
  //      = it further goes into RCTObjcExecutor and tries to get module config from main thread
  //   - The main thread is pending in `RCTCxxBridge.registerAdditionalModuleClasses` where trying to acquire the same lock.
  // To workaround the deadlock, we tend to use the non-locked registration and mutate the bridge internal module data.
  // Since JS thread in this situation is waiting for main thread, it's safe to mutate module data without lock.
  // The only risk should be the internal `_moduleRegistryCreated` flag without lock protection.
  // As we just workaround in `RCTWebSocketExecutor` case, the risk of `_moduleRegistryCreated` race condition should be lower.
  //
  // Learn more about the non-locked initialization:
  // https://github.com/facebook/react-native/blob/757bb75fbf837714725d7b2af62149e8e2a7ee51/React/CxxBridge/RCTCxxBridge.mm#L922-L935
  // See the `_moduleRegistryCreated` NO case
  if ([NSStringFromClass([bridge executorClass]) isEqualToString:@"RCTWebSocketExecutor"]) {
    NSNumber *moduleRegistryCreated = [bridge valueForKey:@"_moduleRegistryCreated"];
    if (![moduleRegistryCreated boolValue]) {
      [bridge registerModulesForClasses:moduleClasses];
      return;
    }
  }

  if (bridge.isLoading) {
    [bridge registerModulesForClasses:moduleClasses];
  } else {
    [bridge registerAdditionalModuleClasses:moduleClasses];
  }
}

- (Class)registerComponentData:(id)viewModule inBridge:(RCTBridge *)bridge forAppId:(NSString *)appId
{
  // Hacky way to get a dictionary with `RCTComponentData` from UIManager.
  NSMutableDictionary<NSString *, RCTComponentData *> *componentDataByName = [[bridge uiManager] valueForKey:@"_componentDataByName"];

  // Call createViewModuleWrapperClassWithModule:appId: dynamically
  Class wrappedViewModuleClass = nil;
  Class viewModuleWrapperClass = NSClassFromString(@"ViewModuleWrapper");
  if (viewModuleWrapperClass && [viewModuleWrapperClass respondsToSelector:@selector(createViewModuleWrapperClassWithModule:appId:)]) {
    wrappedViewModuleClass = ((Class(*)(Class, SEL, id, NSString *))objc_msgSend)(viewModuleWrapperClass, @selector(createViewModuleWrapperClassWithModule:appId:), viewModule, appId);
  }
  
  if (!wrappedViewModuleClass) {
    return nil;
  }
  
  NSString *className = NSStringFromClass(wrappedViewModuleClass);

  if (componentDataByName[className]) {
    // Just in case the component was already registered, let's leave a log that we're overriding it.
    NSLog(@"Overriding ComponentData for view %@", className);
  }

  // Create EXComponentData dynamically
  Class componentDataClass = NSClassFromString(@"EXComponentData");
  id componentData = nil;
  if (componentDataClass && [componentDataClass respondsToSelector:@selector(alloc)]) {
    componentData = ((id(*)(Class, SEL))objc_msgSend)(componentDataClass, @selector(alloc));
    if (componentData && [componentData respondsToSelector:@selector(initWithViewModule:managerClass:bridge:)]) {
      componentData = ((id(*)(id, SEL, id, Class, RCTBridge *))objc_msgSend)(componentData, @selector(initWithViewModule:managerClass:bridge:), viewModule, wrappedViewModuleClass, bridge);
    }
  }
  
  if (componentData) {
    // Cast to RCTComponentData since EXComponentData is a subclass of RCTComponentData
    // Use id cast first, then cast to RCTComponentData
    id componentDataObj = componentData;
    if ([componentDataObj isKindOfClass:[RCTComponentData class]]) {
      componentDataByName[className] = (RCTComponentData *)componentDataObj;
    }
  }

#ifdef RCT_NEW_ARCH_ENABLED
  // Call ExpoFabricView methods dynamically
  Class expoFabricViewClass = NSClassFromString(@"ExpoFabricView");
  if (expoFabricViewClass && [expoFabricViewClass respondsToSelector:@selector(makeViewClassForAppContext:moduleName:viewName:className:)]) {
    // Get moduleName and viewName dynamically
    NSString *moduleName = nil;
    NSString *viewName = nil;
    if ([viewModule respondsToSelector:@selector(moduleName)]) {
      moduleName = ((NSString *(*)(id, SEL))objc_msgSend)(viewModule, @selector(moduleName));
    }
    if ([viewModule respondsToSelector:@selector(viewName)]) {
      viewName = ((NSString *(*)(id, SEL))objc_msgSend)(viewModule, @selector(viewName));
    }
    
    Class viewClass = ((Class(*)(Class, SEL, id, NSString *, NSString *, NSString *))objc_msgSend)(
      expoFabricViewClass,
      @selector(makeViewClassForAppContext:moduleName:viewName:className:),
      _appContext,
      moduleName,
      viewName,
      className
    );
    
    if (viewClass && [RCTComponentViewFactory respondsToSelector:@selector(currentComponentViewFactory)]) {
      id factory = ((id(*)(Class, SEL))objc_msgSend)([RCTComponentViewFactory class], @selector(currentComponentViewFactory));
      if (factory && [factory respondsToSelector:@selector(registerComponentViewClass:)]) {
        ((void(*)(id, SEL, Class))objc_msgSend)(factory, @selector(registerComponentViewClass:), viewClass);
      }
    }
  }
#endif

  return wrappedViewModuleClass;
}

/**
 Bridge's `registerAdditionalModuleClasses:` method doesn't register
 components in UIManager — we need to register them on our own.
 */
- (void)registerLegacyComponentData:(Class)moduleClass inBridge:(RCTBridge *)bridge
{
  // Hacky way to get a dictionary with `RCTComponentData` from UIManager.
  NSMutableDictionary<NSString *, RCTComponentData *> *componentDataByName = [bridge.uiManager valueForKey:@"_componentDataByName"];
  NSString *className = [moduleClass moduleName] ?: NSStringFromClass(moduleClass);

  if ([moduleClass isSubclassOfClass:[RCTViewManager class]] && !componentDataByName[className]) {
    RCTComponentData *componentData = [[RCTComponentData alloc] initWithManagerClass:moduleClass bridge:bridge eventDispatcher:bridge.eventDispatcher];
    componentDataByName[className] = componentData;
  }
}

- (void)assignExportedMethodsKeys:(NSMutableArray<NSMutableDictionary<const NSString *, id> *> *)exportedMethods forModuleName:(const NSString *)moduleName
{
  if (!_exportedMethodsKeys[moduleName]) {
    _exportedMethodsKeys[moduleName] = [NSMutableDictionary dictionary];
  }

  if (!_exportedMethodsReverseKeys[moduleName]) {
    _exportedMethodsReverseKeys[moduleName] = [NSMutableDictionary dictionary];
  }

  for (int i = 0; i < [exportedMethods count]; i++) {
    NSMutableDictionary<const NSString *, id> *methodInfo = exportedMethods[i];

    if (!methodInfo[(NSString *)methodInfoNameKey] || ![methodInfo[methodInfoNameKey] isKindOfClass:[NSString class]]) {
      NSString *reason = [NSString stringWithFormat:@"Method info of a method of module %@ has no method name.", moduleName];
      @throw [NSException exceptionWithName:@"Empty method name in method info" reason:reason userInfo:nil];
    }

    NSString *methodName = methodInfo[(NSString *)methodInfoNameKey];
    NSNumber *previousMethodKey = _exportedMethodsKeys[moduleName][methodName];
    if (previousMethodKey) {
      methodInfo[methodInfoKeyKey] = previousMethodKey;
    } else {
      NSNumber *newKey = @([[_exportedMethodsKeys[moduleName] allValues] count]);
      methodInfo[methodInfoKeyKey] = newKey;
      _exportedMethodsKeys[moduleName][methodName] = newKey;
      _exportedMethodsReverseKeys[moduleName][newKey] = methodName;
    }
  }
}

@end
