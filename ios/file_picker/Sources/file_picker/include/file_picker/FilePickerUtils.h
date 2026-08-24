//
//  FilePickerUtils.h
//  Pods
//
//  Created by Miguel Ruivo on 05/12/2018.
//
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

#ifdef DEBUG
#define Log(fmt, ...)            NSLog((@"\n\n***** " fmt @"\n* %s [Line %d]\n\n\n"), ##__VA_ARGS__, __PRETTY_FUNCTION__, __LINE__)
#else
#define Log(fmt, ...)
#endif

typedef NS_ENUM(NSInteger, MediaType) {
  VIDEO,
  IMAGE,
  MEDIA
};

@interface FilePickerUtils : NSObject
+ (BOOL) clearTemporaryFiles;
+ (NSArray<NSString*>*) resolveType:(NSString*)type withAllowedExtensions:(NSArray<NSString*>*)allowedExtensions;
+ (MediaType) resolveMediaType:(NSString*)type;
+ (NSArray<NSDictionary*>*) resolveFileInfo:(NSArray<NSURL *> *)urls withData:(BOOL)loadData;
// Exports an ipod-library asset to a temporary m4a file.
//
// The export is asynchronous: `completion` is called exactly once, off the
// main thread, with the exported file's URL, or nil when the item cannot be
// exported at all - a cloud-only item that was never downloaded, a DRM
// protected one, or an asset the m4a preset cannot handle.
+ (void) exportMusicAsset:(NSURL*)url withName:(NSString*)name completion:(void (^)(NSURL* exportedUrl))completion;
@end



