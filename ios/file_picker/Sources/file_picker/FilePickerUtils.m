//
//  FilePickerUtils.m
//  file_picker
//
//  Created by Miguel Ruivo on 05/12/2018.
//

#import "FilePickerUtils.h"
#import "FileInfo.h"
#import <AVFoundation/AVFoundation.h>

@implementation FilePickerUtils

+ (BOOL) clearTemporaryFiles {
    NSString *tmpDirectory = NSTemporaryDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *cacheFiles = [fileManager contentsOfDirectoryAtPath:tmpDirectory error:&error];
    
    for (NSString *file in cacheFiles) {
        error = nil;
        [fileManager removeItemAtPath:[tmpDirectory stringByAppendingPathComponent:file] error:&error];
        if(error != nil) {
            Log(@"Failed to remove temporary file %@, aborting. Error: %@", file, error);
            return false;
        }
    }
    Log(@"All temporary files clear");
    return true;
}

+ (NSArray<NSString*> *) resolveType:(NSString*)type withAllowedExtensions:(NSArray<NSString*>*) allowedExtensions {
    
    if ([type isEqualToString:@"any"]) {
        return @[@"public.item"];
    } else if ([type isEqualToString:@"image"]) {
        return @[@"public.image"];
    } else if ([type isEqualToString:@"video"]) {
        return @[@"public.movie"];
    } else if ([type isEqualToString:@"audio"]) {
        return @[@"public.audio"];
    } else if ([type isEqualToString:@"media"]) {
        return @[@"public.image", @"public.video"];
    } else if ([type isEqualToString:@"custom"]) {
        if(allowedExtensions == (id)[NSNull null] || allowedExtensions.count == 0) {
            return nil;
        }
        
        NSMutableArray<NSString*>* utis = [[NSMutableArray<NSString*> alloc] init];
        
        for(int i = 0 ; i<allowedExtensions.count ; i++) {
            NSString * format = [NSString stringWithFormat:@"dummy.%@", allowedExtensions[i]];
            CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[format pathExtension], NULL);
            NSString * UTIString = (__bridge NSString *)(UTI);
            if (UTI) CFRelease(UTI);
            if (!UTI) {
                Log(@"[Skipping type] Resolving type from extension is not supported: %@", allowedExtensions[i]);
                continue;
            } else if ([UTIString containsString:@"dyn."]) {
                Log(@"[Skipping type] Unsupported file type: %@", UTIString);
                continue;
            } else {
                Log(@"Custom file type supported: %@", UTIString);
                [utis addObject: UTIString];
            }
        }
        return utis;
    } else {
        return nil;
    }
}

+ (MediaType) resolveMediaType:(NSString *)type {
    if([type isEqualToString:@"video"]) {
        return VIDEO;
    } else if([type isEqualToString:@"image"]) {
        return IMAGE;
    } else {
        return MEDIA;
    }
}

+ (NSArray<NSDictionary *> *)resolveFileInfo:(NSArray<NSURL *> *)urls withData: (BOOL)loadData {
    
    if(urls == nil) {
        return nil;
    }
    
    NSMutableArray * files = [[NSMutableArray alloc] initWithCapacity:urls.count];
    
    for(NSURL * url in urls) {
        NSString * path = (NSString *)[url path];
        NSDictionary<NSFileAttributeKey, id> * fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        
        [files addObject: [[[FileInfo alloc] initWithPath: path
                                                   andUrl: url
                                                  andName: [path lastPathComponent]
                                                  andSize: [NSNumber numberWithLongLong: [@(fileAttributes.fileSize) longLongValue]]
                                                  andData: loadData ? [NSData dataWithContentsOfFile:path options: 0 error:nil] : nil] toData]];
    }
    
    return files;
}

+ (void) exportMusicAsset:(NSURL*)url withName:(NSString*)name completion:(void (^)(NSURL* exportedUrl))completion {
    // Cloud-only and DRM protected items carry no asset URL, so there is
    // nothing to export. Reported rather than skipped silently, so the caller
    // can tell the difference between "nothing picked" and "nothing usable".
    if(url == nil) {
        Log(@"Couldn't retrieve the audio file path, either it is not locally downloaded or the file is DRM protected.");
        completion(nil);
        return;
    }

    NSString * outputFileType = @"com.apple.m4a-audio";
    AVURLAsset * asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSURL * outputUrl = [self exportDestinationForName:name];

    if(outputUrl == nil) {
        completion(nil);
        return;
    }

    [AVAssetExportSession determineCompatibilityOfExportPreset:AVAssetExportPresetAppleM4A
                                                    withAsset:asset
                                               outputFileType:outputFileType
                                            completionHandler:^(BOOL compatible) {
        if(!compatible) {
            Log(@"The m4a export preset is not compatible with the picked asset.");
            completion(nil);
            return;
        }

        AVAssetExportSession * exporter = [AVAssetExportSession exportSessionWithAsset:asset
                                                                           presetName:AVAssetExportPresetAppleM4A];
        exporter.outputFileType = outputFileType;
        exporter.outputURL = outputUrl;

        [exporter exportAsynchronouslyWithCompletionHandler:^{
            // Every status other than Completed is a failure for our purposes,
            // and the default covers the ones that should never reach a
            // completion handler - leaving the caller waiting forever is worse
            // than reporting a miss.
            if(exporter.status == AVAssetExportSessionStatusCompleted) {
                completion(outputUrl);
            } else {
                Log(@"AVAssetExportSession failed to export: %@", exporter.error.localizedDescription);
                completion(nil);
            }
        }];
    }];
}

// Builds the file to export into: `<tmp>/file_picker_music/<uuid>/<name>.m4a`.
//
// The name is kept because callers surface it to the user, and the uuid
// directory is what makes keeping it safe: two picked tracks can share a
// title, and AVAssetExportSession refuses to write over an existing file, so a
// shared directory would either collide or hand back a stale export left
// behind by an interrupted run.
+ (NSURL*) exportDestinationForName:(NSString*)name {
    NSString * fileName = [self sanitizeFileName:name];
    NSString * directory = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"file_picker_music"]
                            stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

    NSError * error = nil;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error]) {
        Log(@"Couldn't create the export directory: %@", error.localizedDescription);
        return nil;
    }

    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:
                                   [fileName stringByAppendingPathExtension:@"m4a"]]];
}

// Track titles are free text and reach us verbatim: a slash in one (`AC/DC`,
// `Us/Them`) would otherwise be read as a path separator, pointing the export
// at a directory that does not exist. `:` goes too - it is the separator the
// Finder still shows paths with, and it survives round trips badly.
+ (NSString*) sanitizeFileName:(NSString*)name {
    if(name.length == 0) {
        return @"audio";
    }

    NSCharacterSet * illegal = [NSCharacterSet characterSetWithCharactersInString:@"/:"];
    NSString * sanitized = [[name componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];

    return sanitized.length > 0 ? sanitized : @"audio";
}

@end
