#import "ImagePickerManager.h"
#import <React/RCTConvert.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@import MobileCoreServices;

@interface ImagePickerManager ()

@property (nonatomic, strong) UIAlertController *alertController;
@property (nonatomic, strong) UIImagePickerController *picker;
@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, strong) NSDictionary *defaultOptions;
@property (nonatomic, retain) NSMutableDictionary *options, *response;
@property (nonatomic, strong) NSArray *customButtons;

@end

@implementation ImagePickerManager

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(launchCamera:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback;
    [self launchImagePicker:RNImagePickerTargetCamera options:options];
}

RCT_EXPORT_METHOD(launchImageLibrary:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback;
    [self launchImagePicker:RNImagePickerTargetLibrarySingleImage options:options];
}

RCT_EXPORT_METHOD(showImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback; // Save the callback so we can use it from the delegate methods
    self.options = options;
    
    NSString *title = [self.options valueForKey:@"title"];
    if ([title isEqual:[NSNull null]] || title.length == 0) {
        title = nil; // A more visually appealing UIAlertControl is displayed with a nil title rather than title = @""
    }
    NSString *cancelTitle = [self.options valueForKey:@"cancelButtonTitle"];
    NSString *takePhotoButtonTitle = [self.options valueForKey:@"takePhotoButtonTitle"];
    NSString *chooseFromLibraryButtonTitle = [self.options valueForKey:@"chooseFromLibraryButtonTitle"];
    
    
    self.alertController = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        self.callback(@[@{@"didCancel": @YES}]); // Return callback for 'cancel' action (if is required)
    }];
    [self.alertController addAction:cancelAction];
    
    if (![takePhotoButtonTitle isEqual:[NSNull null]] && takePhotoButtonTitle.length > 0) {
        UIAlertAction *takePhotoAction = [UIAlertAction actionWithTitle:takePhotoButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            [self actionHandler:action];
        }];
        [self.alertController addAction:takePhotoAction];
    }
    if (![chooseFromLibraryButtonTitle isEqual:[NSNull null]] && chooseFromLibraryButtonTitle.length > 0) {
        UIAlertAction *chooseFromLibraryAction = [UIAlertAction actionWithTitle:chooseFromLibraryButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            [self actionHandler:action];
        }];
        [self.alertController addAction:chooseFromLibraryAction];
    }
    
    // Add custom buttons to action sheet
    if ([self.options objectForKey:@"customButtons"] && [[self.options objectForKey:@"customButtons"] isKindOfClass:[NSArray class]]) {
        self.customButtons = [self.options objectForKey:@"customButtons"];
        for (NSString *button in self.customButtons) {
            NSString *title = [button valueForKey:@"title"];
            UIAlertAction *customAction = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                [self actionHandler:action];
            }];
            [self.alertController addAction:customAction];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
        while (root.presentedViewController != nil) {
            root = root.presentedViewController;
        }
        
        /* On iPad, UIAlertController presents a popover view rather than an action sheet like on iPhone. We must provide the location
         of the location to show the popover in this case. For simplicity, we'll just display it on the bottom center of the screen
         to mimic an action sheet */
        self.alertController.popoverPresentationController.sourceView = root.view;
        self.alertController.popoverPresentationController.sourceRect = CGRectMake(root.view.bounds.size.width / 2.0, root.view.bounds.size.height, 1.0, 1.0);
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            self.alertController.popoverPresentationController.permittedArrowDirections = 0;
            for (id subview in self.alertController.view.subviews) {
                if ([subview isMemberOfClass:[UIView class]]) {
                    ((UIView *)subview).backgroundColor = [UIColor whiteColor];
                }
            }
        }
        
        [root presentViewController:self.alertController animated:YES completion:nil];
    });
}

- (void)actionHandler:(UIAlertAction *)action
{
    // If button title is one of the keys in the customButtons dictionary return the value as a callback
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title==%@", action.title];
    NSArray *results = [self.customButtons filteredArrayUsingPredicate:predicate];
    if (results.count > 0) {
        NSString *customButtonStr = [[results objectAtIndex:0] objectForKey:@"name"];
        if (customButtonStr) {
            self.callback(@[@{@"customButton": customButtonStr}]);
            return;
        }
    }
    
    if ([action.title isEqualToString:[self.options valueForKey:@"takePhotoButtonTitle"]]) { // Take photo
        [self launchImagePicker:RNImagePickerTargetCamera];
    }
    else if ([action.title isEqualToString:[self.options valueForKey:@"chooseFromLibraryButtonTitle"]]) { // Choose from library
        [self launchImagePicker:RNImagePickerTargetLibrarySingleImage];
    }
}

- (void)launchImagePicker:(RNImagePickerTarget)target options:(NSDictionary *)options
{
    self.options = options;
    [self launchImagePicker:target];
}

- (void)launchImagePicker:(RNImagePickerTarget)target
{
    self.picker = [[UIImagePickerController alloc] init];
    
    if (target == RNImagePickerTargetCamera) {
#if TARGET_IPHONE_SIMULATOR
        self.callback(@[@{@"error": @"Camera not available on simulator"}]);
        return;
#else
        self.picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        if ([[self.options objectForKey:@"cameraType"] isEqualToString:@"front"]) {
            self.picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
        }
        else { // "back"
            self.picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
        }
#endif
    }
    else { // RNImagePickerTargetLibrarySingleImage
        self.picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]
        || [[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        
        if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
            self.picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        }
        else if ([[self.options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
            self.picker.videoQuality = UIImagePickerControllerQualityTypeLow;
        }
        else {
            self.picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
        }
        
        id durationLimit = [self.options objectForKey:@"durationLimit"];
        if (durationLimit) {
            self.picker.videoMaximumDuration = [durationLimit doubleValue];
            self.picker.allowsEditing = NO;
        }
    }
    if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"video"]) {
        self.picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([[self.options objectForKey:@"mediaType"] isEqualToString:@"mixed"]) {
        self.picker.mediaTypes = @[(NSString *)kUTTypeMovie, (NSString *)kUTTypeImage];
    } else {
        self.picker.mediaTypes = @[(NSString *)kUTTypeImage];
    }
    
    if ([[self.options objectForKey:@"allowsEditing"] boolValue]) {
        self.picker.allowsEditing = true;
    }
    self.picker.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.picker.delegate = self;
    
    // Check permissions
    void (^showPickerViewController)() = ^void() {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
            while (root.presentedViewController != nil) {
                root = root.presentedViewController;
            }
            [root presentViewController:self.picker animated:YES completion:nil];
        });
    };
    
    if (target == RNImagePickerTargetCamera) {
        [self checkCameraPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"error": @"Camera permissions not granted"}]);
                return;
            }
            
            showPickerViewController();
        }];
    }
    else { // RNImagePickerTargetLibrarySingleImage
        [self checkPhotosPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"error": @"Photo library permissions not granted"}]);
                return;
            }
            
            showPickerViewController();
        }];
    }
}

- (NSString * _Nullable)originalFilenameForAsset:(PHAsset * _Nullable)asset assetType:(PHAssetResourceType)type {
    if (!asset) { return nil; }
    
    PHAssetResource *originalResource;
    // Get the underlying resources for the PHAsset (PhotoKit)
    NSArray<PHAssetResource *> *pickedAssetResources = [PHAssetResource assetResourcesForAsset:asset];
    
    // Find the original resource (underlying image) for the asset, which has the desired filename
    for (PHAssetResource *resource in pickedAssetResources) {
        if (resource.type == type) {
            originalResource = resource;
        }
    }
    
    return originalResource.originalFilename;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    dispatch_block_t dismissCompletionBlock = ^{
        
        NSURL *imageURL = [info valueForKey:UIImagePickerControllerReferenceURL];
        NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
        
        NSString *fileName;
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
            NSString *tempFileName = [[NSUUID UUID] UUIDString];
            if ([[[self.options objectForKey:@"imageFileType"] stringValue] isEqualToString:@"png"]) {
                fileName = [tempFileName stringByAppendingString:@".png"];
            }
            else {
                fileName = [tempFileName stringByAppendingString:@".jpg"];
            }
        }
        
        // We default to path to the temporary directory
        NSString *path = [[NSTemporaryDirectory()stringByStandardizingPath] stringByAppendingPathComponent:fileName];
        
        // Create the response object
        self.response = [[NSMutableDictionary alloc] init];
        
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) { // PHOTOS
            ALAssetsLibrary *assetLibrary=[[ALAssetsLibrary alloc] init];
            [assetLibrary assetForURL:imageURL resultBlock:^(ALAsset *asset)
             {
                 ALAssetRepresentation *rep = [asset defaultRepresentation];
                 Byte *buffer = (Byte*)malloc(rep.size);
                 NSUInteger buffered = [rep getBytes:buffer fromOffset:0 length:rep.size error:nil];
                 NSData *data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];//this is NSData may be what you want
                 [data writeToFile:path atomically:YES];//you can save image later
             }
                         failureBlock:^(NSError *err)
             {
                 NSLog(@"Error: %@",[err localizedDescription]);
                 
             }
             ];
            
            NSURL *fileURL = [NSURL fileURLWithPath:path];
            NSString *filePath = [fileURL absoluteString];
            [self.response setObject:filePath forKey:@"uri"];
        }
        
        
        
        self.callback(@[self.response]);
    };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:dismissCompletionBlock];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            self.callback(@[@{@"didCancel": @YES}]);
        }];
    });
}

#pragma mark - Helpers

- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    } else {
        callback(NO);
    }
}

- (void)checkPhotosPermissions:(void(^)(BOOL granted))callback
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                callback(YES);
                return;
            }
            else {
                callback(NO);
                return;
            }
        }];
    }
    else {
        callback(NO);
    }
}


- (BOOL)addSkipBackupAttributeToItemAtPath:(NSString *) filePathString
{
    NSURL* URL= [NSURL fileURLWithPath: filePathString];
    if ([[NSFileManager defaultManager] fileExistsAtPath: [URL path]]) {
        NSError *error = nil;
        BOOL success = [URL setResourceValue: [NSNumber numberWithBool: YES]
                                      forKey: NSURLIsExcludedFromBackupKey error: &error];
        
        if(!success){
            NSLog(@"Error excluding %@ from backup %@", [URL lastPathComponent], error);
        }
        return success;
    }
    else {
        NSLog(@"Error setting skip backup attribute: file not found");
        return @NO;
    }
}

#pragma mark - Class Methods

+ (NSDateFormatter * _Nonnull)ISO8601DateFormatter {
    static NSDateFormatter *ISO8601DateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ISO8601DateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        ISO8601DateFormatter.locale = enUSPOSIXLocale;
        ISO8601DateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        ISO8601DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    return ISO8601DateFormatter;
}

@end
