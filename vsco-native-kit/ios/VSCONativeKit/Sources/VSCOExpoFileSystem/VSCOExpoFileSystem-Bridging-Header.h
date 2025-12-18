//
//  VSCOExpoFileSystem-Bridging-Header.h
//  VSCOExpoFileSystem
//
//  Bridging header for mixed-language target (Swift + Objective-C)
//  This header allows Swift code to access Objective-C classes and functions
//

#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>

// Import all Objective-C headers that Swift needs to access
#import "EXFileSystemHandler.h"
#import "ExpoFileSystem.h"
#import "EXFileSystemAssetLibraryHandler.h"
#import "EXFileSystemLocalFileHandler.h"
#import "NSData+EXFileSystem.h"
#import "EXSessionTasks/EXSessionTaskDelegate.h"
#import "EXSessionTasks/EXSessionHandler.h"
#import "EXSessionTasks/EXSessionDownloadTaskDelegate.h"
#import "EXSessionTasks/EXSessionCancelableUploadTaskDelegate.h"
#import "EXSessionTasks/EXSessionUploadTaskDelegate.h"
#import "EXSessionTasks/EXSessionResumableDownloadTaskDelegate.h"
#import "EXSessionTasks/EXTaskHandlersManager.h"
#import "EXSessionTasks/EXSessionTaskDispatcher.h"
