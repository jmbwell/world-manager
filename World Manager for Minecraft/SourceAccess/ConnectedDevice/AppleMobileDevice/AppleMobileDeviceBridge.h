// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const WMMMobileDeviceErrorDomain;

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceSummaries(NSError **error);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceApplicationList(
    NSString *deviceIdentifier,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceApplicationDetails(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppDirectoryListing(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathProbeResults(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSArray<NSString *> *paths,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftLibrarySnapshot(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftMetadataBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSArray<NSDictionary<NSString *, id> *> *items,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftIconBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSArray<NSDictionary<NSString *, id> *> *items,
    NSError **error
);

FOUNDATION_EXPORT NSData * _Nullable
WMMCopyConnectedDeviceAppFileData(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathMetrics(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathMetricsBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSArray<NSString *> *relativePaths,
    NSError **error
);

FOUNDATION_EXPORT BOOL
WMMCopyConnectedDeviceAppSubtreeToLocalDirectory(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSURL *destinationDirectoryURL,
    NSError **error
);

FOUNDATION_EXPORT NSString * _Nullable
WMMInstallLocalDirectoryInConnectedDeviceApp(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *minecraftRootRelativePath,
    NSString *collectionFolderName,
    NSString *preferredDestinationName,
    NSURL *sourceDirectoryURL,
    NSError **error
);

NS_ASSUME_NONNULL_END
