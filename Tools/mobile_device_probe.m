// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#import <Foundation/Foundation.h>
#import "AppleMobileDeviceBridge.h"

static void PrintUsage(void) {
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  mobile_device_probe summary\n");
    fprintf(stderr, "  mobile_device_probe apps\n");
    fprintf(stderr, "  mobile_device_probe details <bundle-id>\n");
    fprintf(stderr, "  mobile_device_probe list <bundle-id> <path>\n");
    fprintf(stderr, "  mobile_device_probe probe-paths <bundle-id> [path ...]\n");
    fprintf(stderr, "  mobile_device_probe mirror <bundle-id> <path> <destination>\n");
}

static NSArray<NSString *> *DefaultCandidatePaths(void) {
    return @[
        @"",
        @".",
        @"./",
        @"/",
        @"Documents",
        @"Documents/",
        @"/Documents",
        @"games",
        @"games/",
        @"/games",
        @"games/com.mojang",
        @"games/com.mojang/",
        @"/games/com.mojang",
        @"Documents/games",
        @"Documents/games/",
        @"/Documents/games",
        @"Documents/games/com.mojang",
        @"Documents/games/com.mojang/",
        @"/Documents/games/com.mojang",
        @"minecraftWorlds",
        @"minecraftWorlds/",
        @"/minecraftWorlds",
        @"Documents/minecraftWorlds",
        @"Documents/minecraftWorlds/",
        @"/Documents/minecraftWorlds"
    ];
}

static NSString *JSONString(id object) {
    if (!object) {
        return @"null";
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || error) {
        return [NSString stringWithFormat:@"<json-error %@>", error.localizedDescription ?: @"unknown"];
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<encoding-error>";
}

static int PrintErrorAndReturn(NSError *error) {
    fprintf(stderr, "Error: %s\n", error.localizedDescription.UTF8String ?: "unknown");
    return 1;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            PrintUsage();
            return 2;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        NSError *error = nil;

        if ([command isEqualToString:@"summary"]) {
            NSDictionary *summary = WMMCopyFirstConnectedDeviceSummary(&error);
            if (!summary) {
                return PrintErrorAndReturn(error);
            }
            printf("%s\n", JSONString(summary).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"apps"]) {
            NSDictionary *apps = WMMCopyFirstConnectedDeviceApplicationList(&error);
            if (!apps) {
                return PrintErrorAndReturn(error);
            }
            printf("%s\n", JSONString(apps).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"details"]) {
            if (argc < 3) {
                PrintUsage();
                return 2;
            }

            NSString *bundleIdentifier = [NSString stringWithUTF8String:argv[2]];
            NSDictionary *details = WMMCopyFirstConnectedDeviceApplicationDetails(bundleIdentifier, &error);
            if (!details) {
                return PrintErrorAndReturn(error);
            }
            printf("%s\n", JSONString(details).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"list"]) {
            if (argc < 4) {
                PrintUsage();
                return 2;
            }

            NSString *bundleIdentifier = [NSString stringWithUTF8String:argv[2]];
            NSString *path = [NSString stringWithUTF8String:argv[3]];
            NSDictionary *listing = WMMCopyFirstConnectedDeviceAppDirectoryListing(bundleIdentifier, path, &error);
            if (!listing) {
                return PrintErrorAndReturn(error);
            }
            printf("%s\n", JSONString(listing).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"probe-paths"]) {
            if (argc < 3) {
                PrintUsage();
                return 2;
            }

            NSString *bundleIdentifier = [NSString stringWithUTF8String:argv[2]];
            NSMutableArray<NSString *> *paths = [NSMutableArray array];
            if (argc > 3) {
                for (int index = 3; index < argc; index += 1) {
                    [paths addObject:[NSString stringWithUTF8String:argv[index]]];
                }
            } else {
                [paths addObjectsFromArray:DefaultCandidatePaths()];
            }

            NSDictionary *probeResults = WMMCopyFirstConnectedDeviceAppPathProbeResults(bundleIdentifier, paths, &error);
            if (!probeResults) {
                return PrintErrorAndReturn(error);
            }
            printf("%s\n", JSONString(probeResults).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"mirror"]) {
            if (argc < 5) {
                PrintUsage();
                return 2;
            }

            NSString *bundleIdentifier = [NSString stringWithUTF8String:argv[2]];
            NSString *path = [NSString stringWithUTF8String:argv[3]];
            NSString *destinationPath = [NSString stringWithUTF8String:argv[4]];
            NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath isDirectory:YES];

            BOOL didCopy = WMMCopyFirstConnectedDeviceAppSubtreeToLocalDirectory(
                bundleIdentifier,
                path,
                destinationURL,
                &error
            );
            if (!didCopy) {
                return PrintErrorAndReturn(error);
            }

            printf("%s\n", destinationURL.path.UTF8String);
            return 0;
        }

        PrintUsage();
        return 2;
    }
}
