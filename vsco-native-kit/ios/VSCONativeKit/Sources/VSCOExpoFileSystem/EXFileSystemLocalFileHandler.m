#import <Foundation/Foundation.h>

#import "EXFileSystemLocalFileHandler.h"
#import "NSData+EXFileSystem.h"

@implementation EXFileSystemLocalFileHandler

+ (void)getInfoForFile:(NSURL *)fileUri
           withOptions:(NSDictionary *)options
              resolver:(EXPromiseResolveBlock)resolve
              rejecter:(EXPromiseRejectBlock)reject
{
  @try {
    if (!fileUri) {
      reject(@"E_INVALID_URL", @"File URI is nil", nil);
      return;
    }
    
    NSString *path = fileUri.path;
    if (!path || path.length == 0) {
      reject(@"E_INVALID_FILE_URL", @"File URI path is empty", nil);
      return;
    }
    
    BOOL isDirectory;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
      NSError *error = nil;
      NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
      if (error) {
        reject(@"E_FILE_INFO_ERROR", [NSString stringWithFormat:@"Failed to get file attributes: %@", error.localizedDescription], error);
        return;
      }
      
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      result[@"exists"] = @(YES);
      result[@"isDirectory"] = @(isDirectory);
      result[@"uri"] = [NSURL fileURLWithPath:path].absoluteString;
      if (options[@"md5"]) {
        NSData *fileData = [NSData dataWithContentsOfFile:path];
        if (fileData) {
          result[@"md5"] = [fileData md5String];
        }
      }
      result[@"size"] = @([EXFileSystemLocalFileHandler getFileSize:path attributes:attributes]);
      // Uses required reason API based on the following reason: 0A2A.1
      if (attributes.fileModificationDate) {
        result[@"modificationTime"] = @(attributes.fileModificationDate.timeIntervalSince1970);
      }
      resolve(result);
    } else {
      resolve(@{@"exists": @(NO), @"isDirectory": @(NO)});
    }
  } @catch (NSException *exception) {
    reject(@"E_FILE_INFO_EXCEPTION", [NSString stringWithFormat:@"Exception getting file info: %@", exception.reason], nil);
  }
}

+ (unsigned long long)getFileSize:(NSString *)path attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes
{
  if (attributes.fileType != NSFileTypeDirectory) {
    return attributes.fileSize;
  }
  
  // The path is pointing to the folder
  NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
  NSEnumerator *contentsEnumurator = [contents objectEnumerator];
  NSString *file;
  unsigned long long folderSize = 0;
  while (file = [contentsEnumurator nextObject]) {
    NSString *filePath = [path stringByAppendingPathComponent:file];
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    folderSize += [EXFileSystemLocalFileHandler getFileSize:filePath attributes:fileAttributes];
  }
  
  return folderSize;
}

+ (void)copyFrom:(NSURL *)from
              to:(NSURL *)to
        resolver:(EXPromiseResolveBlock)resolve
        rejecter:(EXPromiseRejectBlock)reject
{
  NSString *fromPath = [from.path stringByStandardizingPath];
  NSString *toPath = [to.path stringByStandardizingPath];
  
  NSError *error;
  if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
    if (![[NSFileManager defaultManager] removeItemAtPath:toPath error:&error]) {
      reject(@"E_FILE_NOT_COPIED",
             [NSString stringWithFormat:@"File '%@' could not be copied to '%@' because a file already exists at "
              "the destination and could not be deleted.", from, to],
             error);
      return;
    }
  }
  
  if ([[NSFileManager defaultManager] copyItemAtPath:fromPath toPath:toPath error:&error]) {
    resolve(nil);
  } else {
    reject(@"E_FILE_NOT_COPIED",
           [NSString stringWithFormat:@"File '%@' could not be copied to '%@'.", from, to],
           error);
  }
}

@end
