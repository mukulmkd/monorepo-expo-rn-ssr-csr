#import <Foundation/Foundation.h>
// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXSessionUploadTaskDelegate.h"
#import "EXTaskHandlersManager.h"

typedef void (^EXUploadDelegateOnSendCallback)(NSURLSessionUploadTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend);

@interface EXSessionCancelableUploadTaskDelegate : EXSessionUploadTaskDelegate

- (nonnull instancetype)initWithResolve:(EXPromiseResolveBlock)resolve
                                 reject:(EXPromiseRejectBlock)reject
                         onSendCallback:(EXUploadDelegateOnSendCallback)onSendCallback
                       resumableManager:(EXTaskHandlersManager *)manager
                                   uuid:(NSString *)uuid;

@end
