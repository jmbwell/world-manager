//
//  AppleMobileDeviceBridge.h
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const WMMMobileDeviceErrorDomain;

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyFirstConnectedDeviceSummary(NSError **error);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyFirstConnectedDeviceApplicationList(NSError **error);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyFirstConnectedDeviceApplicationDetails(
    NSString *bundleIdentifier,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyFirstConnectedDeviceAppDirectoryListing(
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyFirstConnectedDeviceAppPathProbeResults(
    NSString *bundleIdentifier,
    NSArray<NSString *> *paths,
    NSError **error
);

FOUNDATION_EXPORT BOOL
WMMCopyFirstConnectedDeviceAppSubtreeToLocalDirectory(
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSURL *destinationDirectoryURL,
    NSError **error
);

NS_ASSUME_NONNULL_END
