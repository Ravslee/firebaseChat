//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "AppState.h"
#import "Constants.h"
#import "FCViewController.h"

@import Photos;

@import Firebase;
@import GoogleMobileAds;

/**
 * AdMob ad unit IDs are not currently stored inside the google-services.plist file. Developers
 * using AdMob can store them as custom values in another plist, or simply use constants. Note that
 * these ad units are configured to return only test ads, and should not be used outside this sample.
 */
static NSString* const kBannerAdUnitID = @"ca-app-pub-3940256099942544/2934735716";

@interface FCViewController ()<UITableViewDataSource, UITableViewDelegate,
UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
  int _msglength;
  FIRDatabaseHandle _refHandle;
}

@property(nonatomic, weak) IBOutlet UITextField *textField;
@property(nonatomic, weak) IBOutlet UIButton *sendButton;

@property(nonatomic, weak) IBOutlet GADBannerView *banner;
@property(nonatomic, weak) IBOutlet UITableView *clientTable;

@property (strong, nonatomic) FIRDatabaseReference *ref;
@property (strong, nonatomic) NSMutableArray<FIRDataSnapshot *> *messages;
@property (strong, nonatomic) FIRStorageReference *storageRef;
@property (nonatomic, strong) FIRRemoteConfig *remoteConfig;

@end

@implementation FCViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  _msglength = 10;
  _messages = [[NSMutableArray alloc] init];
  [_clientTable registerClass:UITableViewCell.self forCellReuseIdentifier:@"tableViewCell"];

  [self configureDatabase];
  [self configureStorage];
  [self configureRemoteConfig];
  [self fetchConfig];
  [self loadAd];
  [self logViewLoaded];
}

- (void)dealloc {
  [[_ref child:@"messages"] removeObserverWithHandle:_refHandle];
}

- (void)configureDatabase {
  _ref = [[FIRDatabase database] reference];
  // Listen for new messages in the Firebase database
  _refHandle = [[_ref child:@"messages"] observeEventType:FIRDataEventTypeChildAdded withBlock:^(FIRDataSnapshot *snapshot) {
    [_messages addObject:snapshot];
    [_clientTable insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:_messages.count-1 inSection:0]] withRowAnimation: UITableViewRowAnimationAutomatic];
  }];
}

- (void)configureStorage {
  NSString *storageUrl = [FIRApp defaultApp].options.storageBucket;
  self.storageRef = [[FIRStorage storage] referenceForURL:[NSString stringWithFormat:@"gs://%@", storageUrl]];
}

- (void)configureRemoteConfig {
  _remoteConfig = [FIRRemoteConfig remoteConfig];
  // Create Remote Config Setting to enable developer mode.
  // Fetching configs from the server is normally limited to 5 requests per hour.
  // Enabling developer mode allows many more requests to be made per hour, so developers
  // can test different config values during development.
  FIRRemoteConfigSettings *remoteConfigSettings = [[FIRRemoteConfigSettings alloc] initWithDeveloperModeEnabled:YES];
  self.remoteConfig.configSettings = remoteConfigSettings;
}

- (void)fetchConfig {
  long expirationDuration = 3600;
  // If in developer mode cacheExpiration is set to 0 so each fetch will retrieve values from
  // the server.
  if (self.remoteConfig.configSettings.isDeveloperModeEnabled) {
    expirationDuration = 0;
  }

  // cacheExpirationSeconds is set to cacheExpiration here, indicating that any previously
  // fetched and cached config would be considered expired because it would have been fetched
  // more than cacheExpiration seconds ago. Thus the next fetch would go to the server unless
  // throttling is in progress. The default expiration duration is 43200 (12 hours).
  [self.remoteConfig fetchWithExpirationDuration:expirationDuration completionHandler:^(FIRRemoteConfigFetchStatus status, NSError *error) {
    if (status == FIRRemoteConfigFetchStatusSuccess) {
      NSLog(@"Config fetched!");
      [_remoteConfig activateFetched];
      FIRRemoteConfigValue *friendlyMsgLength = _remoteConfig[@"friendly_msg_length"];
      if (friendlyMsgLength.source != FIRRemoteConfigSourceStatic) {
        _msglength = friendlyMsgLength.numberValue.intValue;
        NSLog(@"Friendly msg length config: %d", _msglength);
      }
    } else {
      NSLog(@"Config not fetched");
      NSLog(@"Error %@", error);
    }
  }];
}

- (IBAction)didPressFreshConfig:(id)sender {
  [self fetchConfig];
}

- (IBAction)didSendMessage:(UIButton *)sender {
  [self textFieldShouldReturn:_textField];
}

- (IBAction)didPressCrash:(id)sender {
  FIRCrashLog(@"Cause Crash button clicked");
  assert(NO);
}

- (void)logViewLoaded {
  // Log that the view did load, FIRCrashNSLog is used here so the log message will be
  // shown in the console output. If FIRCrashLog is used the message is not shown in
  // the console output.
  FIRCrashNSLog(@"View loaded");
}

- (void)loadAd {
  self.banner.adUnitID = kBannerAdUnitID;
  self.banner.rootViewController = self;
  [self.banner loadRequest:[GADRequest request]];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(nonnull NSString *)string {
  NSString *text = textField.text;
  if (!text) {
    return YES;
  }
  long newLength = text.length + string.length - range.length;
  return (newLength <= _msglength);
}

// UITableViewDataSource protocol methods
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return [_messages count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
  // Dequeue cell
  UITableViewCell *cell = [_clientTable dequeueReusableCellWithIdentifier:@"tableViewCell" forIndexPath:indexPath];

  // Unpack message from Firebase DataSnapshot
  FIRDataSnapshot *messageSnapshot = _messages[indexPath.row];
  NSDictionary<NSString *, NSString *> *message = messageSnapshot.value;
  NSString *name = message[MessageFieldsname];
  NSString *imageURL = message[MessageFieldsimageURL];
  if (imageURL) {
    if ([imageURL hasPrefix:@"gs://"]) {
      [[[FIRStorage storage] referenceForURL:imageURL] dataWithMaxSize:INT64_MAX
                                                            completion:^(NSData *data, NSError *error) {
        if (error) {
          NSLog(@"Error downloading: %@", error);
          return;
        }
        cell.imageView.image = [UIImage imageWithData:data];
      }];
    } else {
      cell.imageView.image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageURL]]];
    }
    cell.textLabel.text = [NSString stringWithFormat:@"sent by: %@", name];
  } else {
    NSString *text = message[MessageFieldstext];
    cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", name, text];
    cell.imageView.image = [UIImage imageNamed: @"ic_account_circle"];
    NSString *photoURL = message[MessageFieldsphotoURL];
    if (photoURL) {
      NSURL *URL = [NSURL URLWithString:photoURL];
      if (URL) {
        NSData *data = [NSData dataWithContentsOfURL:URL];
        if (data) {
          cell.imageView.image = [UIImage imageWithData:data];
        }
      }
    }
  }
  return cell;
}

// UITextViewDelegate protocol methods
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [self sendMessage:@{MessageFieldstext: textField.text}];
  textField.text = @"";
  return YES;
}

- (void)sendMessage:(NSDictionary *)data {
  NSMutableDictionary *mdata = [data mutableCopy];
  mdata[MessageFieldsname] = [AppState sharedInstance].displayName;
  NSURL *photoURL = AppState.sharedInstance.photoURL;
  if (photoURL) {
    mdata[MessageFieldsphotoURL] = [photoURL absoluteString];
  }

  // Push data to Firebase Database
  [[[_ref child:@"messages"] childByAutoId] setValue:mdata];
}

# pragma mark - Image Picker

- (IBAction)didTapAddPhoto:(id)sender {
  UIImagePickerController * picker = [[UIImagePickerController alloc] init];
  picker.delegate = self;
  if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
  } else {
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  }

  [self presentViewController:picker animated:YES completion:NULL];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary *)info {
  [picker dismissViewControllerAnimated:YES completion:NULL];

  NSURL *referenceURL = info[UIImagePickerControllerReferenceURL];
  // if it's a photo from the library, not an image from the camera
  if (referenceURL) {
    PHFetchResult* assets = [PHAsset fetchAssetsWithALAssetURLs:@[referenceURL] options:nil];
    PHAsset *asset = [assets firstObject];
    [asset requestContentEditingInputWithOptions:nil
                               completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
                                 NSURL *imageFile = contentEditingInput.fullSizeImageURL;
                                 NSString *filePath = [NSString stringWithFormat:@"%@/%lld/%@",
                                                       [FIRAuth auth].currentUser.uid,
                                                       (long long)([[NSDate date] timeIntervalSince1970] * 1000.0),
                                                       [referenceURL lastPathComponent]];
                                 [[_storageRef child:filePath]
                                            putFile:imageFile metadata:nil
                                          completion:^(FIRStorageMetadata *metadata, NSError *error) {
                                            if (error) {
                                              NSLog(@"Error uploading: %@", error);
                                              return;
                                            }
                                            [self sendMessage:@{MessageFieldsimageURL:[_storageRef child:metadata.path].description}];
                                    }
                                ];
                             }];
  } else {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
    NSString *imagePath =
    [NSString stringWithFormat:@"%@/%lld.jpg",
     [FIRAuth auth].currentUser.uid,
     (long long)([[NSDate date] timeIntervalSince1970] * 1000.0)];
    FIRStorageMetadata *metadata = [FIRStorageMetadata new];
    metadata.contentType = @"image/jpeg";
    [[_storageRef child:imagePath] putData:imageData metadata:metadata
                                completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
                                  if (error) {
                                    NSLog(@"Error uploading: %@", error);
                                    return;
                                  }
                                  [self sendMessage:@{MessageFieldsimageURL:[_storageRef child:metadata.path].description}];
                                }];
  }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  [picker dismissViewControllerAnimated:YES completion:NULL];
}

- (IBAction)signOut:(UIButton *)sender {
  FIRAuth *firebaseAuth = [FIRAuth auth];
  NSError *signOutError;
  BOOL status = [firebaseAuth signOut:&signOutError];
  if (!status) {
    NSLog(@"Error signing out: %@", signOutError);
    return;
  }
  [AppState sharedInstance].signedIn = false;
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDestructive handler:nil];
    [alert addAction:dismissAction];
    [self presentViewController:alert animated: true completion: nil];
  });
}

@end
