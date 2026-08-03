// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#import "AppleMobileDeviceBridge.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <limits.h>

NSErrorDomain const WMMMobileDeviceErrorDomain = @"WMMMobileDeviceErrorDomain";

static BOOL WMMMobileDeviceVerboseLoggingEnabled(void) {
    static BOOL initialized = NO;
    static BOOL enabled = NO;
    if (!initialized) {
        NSString *value = [[[NSProcessInfo processInfo] environment][@"WMM_MOBILEDEVICE_VERBOSE_LOGGING"] lowercaseString];
        enabled = [value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"];
        initialized = YES;
    }
    return enabled;
}

#define WMMBridgeLog(...) do { \
    if (WMMMobileDeviceVerboseLoggingEnabled()) { \
        NSLog(__VA_ARGS__); \
    } \
} while (0)

typedef struct am_device *AMDeviceRef;
typedef struct am_device_notification *AMDeviceNotificationRef;
typedef struct amd_service_connection *AMDServiceConnectionRef;
typedef struct afc_connection *AFCConnectionRef;
typedef struct afc_directory *AFCDirectoryRef;
typedef CFTypeRef AFCFileDescriptorRef;
typedef CFTypeRef AFCIteratorRef;
typedef uint32_t service_conn_t;

struct am_device_notification_callback_info {
    AMDeviceRef dev;
    unsigned int msg;
};

typedef void (*AMDeviceNotificationCallback)(
    struct am_device_notification_callback_info *info,
    void *context
);

enum {
    WMMAMDConnectedMessage = 1
};

typedef int (*AMDeviceNotificationSubscribeFn)(
    AMDeviceNotificationCallback callback,
    int unused1,
    int unused2,
    void *context,
    AMDeviceNotificationRef *subscription
);
typedef int (*AMDeviceNotificationUnsubscribeFn)(AMDeviceNotificationRef subscription);
typedef AMDeviceRef (*AMDeviceRetainFn)(AMDeviceRef device);
typedef int (*AMDeviceReleaseFn)(AMDeviceRef device);
typedef int (*AMDeviceConnectFn)(AMDeviceRef device);
typedef int (*AMDeviceDisconnectFn)(AMDeviceRef device);
typedef int (*AMDeviceIsPairedFn)(AMDeviceRef device);
typedef int (*AMDeviceValidatePairingFn)(AMDeviceRef device);
typedef int (*AMDeviceStartSessionFn)(AMDeviceRef device);
typedef int (*AMDeviceStopSessionFn)(AMDeviceRef device);
typedef CFStringRef _Nullable (*AMDeviceCopyDeviceIdentifierFn)(AMDeviceRef device);
typedef CFTypeRef _Nullable (*AMDeviceCopyValueFn)(AMDeviceRef device, CFStringRef _Nullable domain, CFStringRef name);
typedef int (*AMDeviceLookupApplicationsFn)(
    AMDeviceRef device,
    CFDictionaryRef _Nullable options,
    CFDictionaryRef _Nullable *result
);
typedef int (*AMDeviceCreateHouseArrestServiceFn)(
    AMDeviceRef device,
    CFStringRef identifier,
    CFDictionaryRef _Nullable options,
    AFCConnectionRef _Nullable *connection
);
typedef int (*AMDeviceSecureStartServiceFn)(
    AMDeviceRef device,
    CFStringRef serviceName,
    CFDictionaryRef _Nullable options,
    AMDServiceConnectionRef _Nullable *serviceConnection
);
typedef int (*AMDeviceStartHouseArrestServiceFn)(
    AMDeviceRef device,
    CFStringRef identifier,
    CFDictionaryRef _Nullable options,
    service_conn_t *handle,
    void * _Nullable *secureContext
);
typedef int (*AMDServiceConnectionSendMessageFn)(
    AMDServiceConnectionRef serviceConnection,
    CFPropertyListRef message,
    int timeout
);
typedef int (*AMDServiceConnectionReceiveMessageFn)(
    AMDServiceConnectionRef serviceConnection,
    CFPropertyListRef _Nullable *message,
    int timeout
);
typedef void (*AMDServiceConnectionInvalidateFn)(AMDServiceConnectionRef serviceConnection);
typedef int (*AMDServiceConnectionGetSocketFn)(AMDServiceConnectionRef serviceConnection);
typedef void * _Nullable (*AMDServiceConnectionGetSecureIOContextFn)(AMDServiceConnectionRef serviceConnection);
typedef AFCConnectionRef _Nullable (*AFCConnectionCreateFn)(
    CFAllocatorRef allocator,
    int socket,
    uint32_t unused1,
    void * _Nullable unused2,
    void * _Nullable unused3
);
typedef void (*AFCConnectionSetSecureContextFn)(AFCConnectionRef connection, void * _Nullable secureContext);
typedef int (*AFCConnectionOpenFn)(service_conn_t handle, unsigned int ioTimeout, AFCConnectionRef *connection);
typedef int (*AFCConnectionCloseFn)(AFCConnectionRef connection);
typedef int (*AFCDirectoryOpenFn)(AFCConnectionRef connection, const char *path, AFCDirectoryRef *directory);
typedef int (*AFCDirectoryReadFn)(AFCConnectionRef connection, AFCDirectoryRef directory, char **directoryEntry);
typedef int (*AFCDirectoryCloseFn)(AFCConnectionRef connection, AFCDirectoryRef directory);
typedef int (*AFCFileInfoOpenFn)(AFCConnectionRef connection, const char *path, AFCIteratorRef *iterator);
typedef int (*AFCKeyValueReadFn)(AFCIteratorRef iterator, char **key, char **value);
typedef int (*AFCKeyValueCloseFn)(AFCIteratorRef iterator);
typedef int (*AFCFileRefOpenFn)(AFCConnectionRef connection, const char *path, uint64_t mode, AFCFileDescriptorRef *fileDescriptor);
typedef int (*AFCFileRefReadFn)(AFCConnectionRef connection, AFCFileDescriptorRef fileDescriptor, void *buffer, size_t *length);
typedef int (*AFCFileRefWriteFn)(AFCConnectionRef connection, AFCFileDescriptorRef fileDescriptor, const void *buffer, uint32_t length);
typedef int (*AFCFileRefCloseFn)(AFCConnectionRef connection, AFCFileDescriptorRef fileDescriptor);
typedef int (*AFCDirectoryCreateFn)(AFCConnectionRef connection, const char *path);
typedef int (*AFCRenamePathFn)(AFCConnectionRef connection, const char *sourcePath, const char *destinationPath);
typedef int (*AFCRemovePathFn)(AFCConnectionRef connection, const char *path);

typedef struct {
    void *handle;
    AMDeviceNotificationSubscribeFn AMDeviceNotificationSubscribe;
    AMDeviceNotificationUnsubscribeFn AMDeviceNotificationUnsubscribe;
    AMDeviceRetainFn AMDeviceRetain;
    AMDeviceReleaseFn AMDeviceRelease;
    AMDeviceConnectFn AMDeviceConnect;
    AMDeviceDisconnectFn AMDeviceDisconnect;
    AMDeviceIsPairedFn AMDeviceIsPaired;
    AMDeviceValidatePairingFn AMDeviceValidatePairing;
    AMDeviceStartSessionFn AMDeviceStartSession;
    AMDeviceStopSessionFn AMDeviceStopSession;
    AMDeviceCopyDeviceIdentifierFn AMDeviceCopyDeviceIdentifier;
    AMDeviceCopyValueFn AMDeviceCopyValue;
    AMDeviceLookupApplicationsFn AMDeviceLookupApplications;
    AMDeviceCreateHouseArrestServiceFn AMDeviceCreateHouseArrestService;
    AMDeviceSecureStartServiceFn AMDeviceSecureStartService;
    AMDeviceStartHouseArrestServiceFn AMDeviceStartHouseArrestService;
    AMDServiceConnectionSendMessageFn AMDServiceConnectionSendMessage;
    AMDServiceConnectionReceiveMessageFn AMDServiceConnectionReceiveMessage;
    AMDServiceConnectionInvalidateFn AMDServiceConnectionInvalidate;
    AMDServiceConnectionGetSocketFn AMDServiceConnectionGetSocket;
    AMDServiceConnectionGetSecureIOContextFn AMDServiceConnectionGetSecureIOContext;
    AFCConnectionCreateFn AFCConnectionCreate;
    AFCConnectionSetSecureContextFn AFCConnectionSetSecureContext;
    AFCConnectionOpenFn AFCConnectionOpen;
    AFCConnectionCloseFn AFCConnectionClose;
    AFCDirectoryOpenFn AFCDirectoryOpen;
    AFCDirectoryReadFn AFCDirectoryRead;
    AFCDirectoryCloseFn AFCDirectoryClose;
    AFCFileInfoOpenFn AFCFileInfoOpen;
    AFCKeyValueReadFn AFCKeyValueRead;
    AFCKeyValueCloseFn AFCKeyValueClose;
    AFCFileRefOpenFn AFCFileRefOpen;
    AFCFileRefReadFn AFCFileRefRead;
    AFCFileRefWriteFn AFCFileRefWrite;
    AFCFileRefCloseFn AFCFileRefClose;
    AFCDirectoryCreateFn AFCDirectoryCreate;
    AFCRenamePathFn AFCRenamePath;
    AFCRemovePathFn AFCRemovePath;
} WMMMobileDeviceFunctions;

typedef struct {
    WMMMobileDeviceFunctions *functions;
    CFRunLoopRef runLoop;
    NSMutableArray<NSValue *> *devices;
} WMMDeviceCollectionContext;

static NSString *WMMDeviceStringValue(WMMMobileDeviceFunctions *functions, AMDeviceRef device, CFStringRef key);
static NSInteger WMMConnectionPreferenceRank(AMDeviceRef device);

static NSError *WMMMakeError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:WMMMobileDeviceErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey: description
    }];
}

static void *WMMLoadSymbol(void *handle, const char *name) {
    return dlsym(handle, name);
}

static BOOL WMMLoadFunctions(WMMMobileDeviceFunctions *functions, NSError **error) {
    static const char *paths[] = {
        "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
        "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
    };

    void *frameworkHandle = NULL;
    for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]); index += 1) {
        frameworkHandle = dlopen(paths[index], RTLD_NOW | RTLD_LOCAL);
        if (frameworkHandle != NULL) {
            break;
        }
    }

    if (frameworkHandle == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(1, @"MobileDevice.framework is not available.");
        }
        return NO;
    }

    memset(functions, 0, sizeof(*functions));
    functions->handle = frameworkHandle;
    functions->AMDeviceNotificationSubscribe = (AMDeviceNotificationSubscribeFn)WMMLoadSymbol(frameworkHandle, "AMDeviceNotificationSubscribe");
    functions->AMDeviceNotificationUnsubscribe = (AMDeviceNotificationUnsubscribeFn)WMMLoadSymbol(frameworkHandle, "AMDeviceNotificationUnsubscribe");
    functions->AMDeviceRetain = (AMDeviceRetainFn)WMMLoadSymbol(frameworkHandle, "AMDeviceRetain");
    functions->AMDeviceRelease = (AMDeviceReleaseFn)WMMLoadSymbol(frameworkHandle, "AMDeviceRelease");
    functions->AMDeviceConnect = (AMDeviceConnectFn)WMMLoadSymbol(frameworkHandle, "AMDeviceConnect");
    functions->AMDeviceDisconnect = (AMDeviceDisconnectFn)WMMLoadSymbol(frameworkHandle, "AMDeviceDisconnect");
    functions->AMDeviceIsPaired = (AMDeviceIsPairedFn)WMMLoadSymbol(frameworkHandle, "AMDeviceIsPaired");
    functions->AMDeviceValidatePairing = (AMDeviceValidatePairingFn)WMMLoadSymbol(frameworkHandle, "AMDeviceValidatePairing");
    functions->AMDeviceStartSession = (AMDeviceStartSessionFn)WMMLoadSymbol(frameworkHandle, "AMDeviceStartSession");
    functions->AMDeviceStopSession = (AMDeviceStopSessionFn)WMMLoadSymbol(frameworkHandle, "AMDeviceStopSession");
    functions->AMDeviceCopyDeviceIdentifier = (AMDeviceCopyDeviceIdentifierFn)WMMLoadSymbol(frameworkHandle, "AMDeviceCopyDeviceIdentifier");
    functions->AMDeviceCopyValue = (AMDeviceCopyValueFn)WMMLoadSymbol(frameworkHandle, "AMDeviceCopyValue");
    functions->AMDeviceLookupApplications = (AMDeviceLookupApplicationsFn)WMMLoadSymbol(frameworkHandle, "AMDeviceLookupApplications");
    functions->AMDeviceCreateHouseArrestService = (AMDeviceCreateHouseArrestServiceFn)WMMLoadSymbol(frameworkHandle, "AMDeviceCreateHouseArrestService");
    functions->AMDeviceSecureStartService = (AMDeviceSecureStartServiceFn)WMMLoadSymbol(frameworkHandle, "AMDeviceSecureStartService");
    functions->AMDeviceStartHouseArrestService = (AMDeviceStartHouseArrestServiceFn)WMMLoadSymbol(frameworkHandle, "AMDeviceStartHouseArrestService");
    functions->AMDServiceConnectionSendMessage = (AMDServiceConnectionSendMessageFn)WMMLoadSymbol(frameworkHandle, "AMDServiceConnectionSendMessage");
    functions->AMDServiceConnectionReceiveMessage = (AMDServiceConnectionReceiveMessageFn)WMMLoadSymbol(frameworkHandle, "AMDServiceConnectionReceiveMessage");
    functions->AMDServiceConnectionInvalidate = (AMDServiceConnectionInvalidateFn)WMMLoadSymbol(frameworkHandle, "AMDServiceConnectionInvalidate");
    functions->AMDServiceConnectionGetSocket = (AMDServiceConnectionGetSocketFn)WMMLoadSymbol(frameworkHandle, "AMDServiceConnectionGetSocket");
    functions->AMDServiceConnectionGetSecureIOContext = (AMDServiceConnectionGetSecureIOContextFn)WMMLoadSymbol(frameworkHandle, "AMDServiceConnectionGetSecureIOContext");
    functions->AFCConnectionCreate = (AFCConnectionCreateFn)WMMLoadSymbol(frameworkHandle, "AFCConnectionCreate");
    functions->AFCConnectionSetSecureContext = (AFCConnectionSetSecureContextFn)WMMLoadSymbol(frameworkHandle, "AFCConnectionSetSecureContext");
    functions->AFCConnectionOpen = (AFCConnectionOpenFn)WMMLoadSymbol(frameworkHandle, "AFCConnectionOpen");
    functions->AFCConnectionClose = (AFCConnectionCloseFn)WMMLoadSymbol(frameworkHandle, "AFCConnectionClose");
    functions->AFCDirectoryOpen = (AFCDirectoryOpenFn)WMMLoadSymbol(frameworkHandle, "AFCDirectoryOpen");
    functions->AFCDirectoryRead = (AFCDirectoryReadFn)WMMLoadSymbol(frameworkHandle, "AFCDirectoryRead");
    functions->AFCDirectoryClose = (AFCDirectoryCloseFn)WMMLoadSymbol(frameworkHandle, "AFCDirectoryClose");
    functions->AFCFileInfoOpen = (AFCFileInfoOpenFn)WMMLoadSymbol(frameworkHandle, "AFCFileInfoOpen");
    functions->AFCKeyValueRead = (AFCKeyValueReadFn)WMMLoadSymbol(frameworkHandle, "AFCKeyValueRead");
    functions->AFCKeyValueClose = (AFCKeyValueCloseFn)WMMLoadSymbol(frameworkHandle, "AFCKeyValueClose");
    functions->AFCFileRefOpen = (AFCFileRefOpenFn)WMMLoadSymbol(frameworkHandle, "AFCFileRefOpen");
    functions->AFCFileRefRead = (AFCFileRefReadFn)WMMLoadSymbol(frameworkHandle, "AFCFileRefRead");
    functions->AFCFileRefWrite = (AFCFileRefWriteFn)WMMLoadSymbol(frameworkHandle, "AFCFileRefWrite");
    functions->AFCFileRefClose = (AFCFileRefCloseFn)WMMLoadSymbol(frameworkHandle, "AFCFileRefClose");
    functions->AFCDirectoryCreate = (AFCDirectoryCreateFn)WMMLoadSymbol(frameworkHandle, "AFCDirectoryCreate");
    functions->AFCRenamePath = (AFCRenamePathFn)WMMLoadSymbol(frameworkHandle, "AFCRenamePath");
    functions->AFCRemovePath = (AFCRemovePathFn)WMMLoadSymbol(frameworkHandle, "AFCRemovePath");

    if (functions->AMDeviceNotificationSubscribe == NULL ||
        functions->AMDeviceNotificationUnsubscribe == NULL ||
        functions->AMDeviceRetain == NULL ||
        functions->AMDeviceRelease == NULL ||
        functions->AMDeviceConnect == NULL ||
        functions->AMDeviceDisconnect == NULL ||
        functions->AMDeviceIsPaired == NULL ||
        functions->AMDeviceValidatePairing == NULL ||
        functions->AMDeviceStartSession == NULL ||
        functions->AMDeviceStopSession == NULL ||
        functions->AMDeviceCopyDeviceIdentifier == NULL ||
        functions->AMDeviceCopyValue == NULL ||
        functions->AMDeviceLookupApplications == NULL ||
        functions->AMDeviceCreateHouseArrestService == NULL ||
        functions->AMDeviceSecureStartService == NULL ||
        functions->AMDeviceStartHouseArrestService == NULL ||
        functions->AMDServiceConnectionSendMessage == NULL ||
        functions->AMDServiceConnectionReceiveMessage == NULL ||
        functions->AMDServiceConnectionInvalidate == NULL ||
        functions->AMDServiceConnectionGetSocket == NULL ||
        functions->AMDServiceConnectionGetSecureIOContext == NULL ||
        functions->AFCConnectionCreate == NULL ||
        functions->AFCConnectionSetSecureContext == NULL ||
        functions->AFCConnectionOpen == NULL ||
        functions->AFCConnectionClose == NULL ||
        functions->AFCDirectoryOpen == NULL ||
        functions->AFCDirectoryRead == NULL ||
        functions->AFCDirectoryClose == NULL ||
        functions->AFCFileInfoOpen == NULL ||
        functions->AFCKeyValueRead == NULL ||
        functions->AFCKeyValueClose == NULL ||
        functions->AFCFileRefOpen == NULL ||
        functions->AFCFileRefRead == NULL ||
        functions->AFCFileRefClose == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(2, @"MobileDevice.framework symbols could not be loaded.");
        }
        dlclose(frameworkHandle);
        memset(functions, 0, sizeof(*functions));
        return NO;
    }

    return YES;
}

static void WMMDeviceNotificationCallback(struct am_device_notification_callback_info *info, void *contextPointer) {
    if (info == NULL || contextPointer == NULL || info->msg != WMMAMDConnectedMessage) {
        return;
    }

    WMMDeviceCollectionContext *context = contextPointer;
    AMDeviceRef retainedDevice = context->functions->AMDeviceRetain(info->dev);
    [context->devices addObject:[NSValue valueWithPointer:retainedDevice]];
}

static NSArray<NSValue *> *WMMCopyConnectedDevices(WMMMobileDeviceFunctions *functions, NSError **error) {
    WMMDeviceCollectionContext context = {
        .functions = functions,
        .runLoop = CFRunLoopGetCurrent(),
        .devices = [NSMutableArray array]
    };

    AMDeviceNotificationRef subscription = NULL;
    const int subscribeStatus = functions->AMDeviceNotificationSubscribe(
        WMMDeviceNotificationCallback,
        0,
        0,
        &context,
        &subscription
    );
    if (subscribeStatus != 0) {
        if (error != NULL) {
            *error = WMMMakeError(3, @"No connected iPhone or iPad was detected through MobileDevice.framework.");
        }
        return NULL;
    }

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    functions->AMDeviceNotificationUnsubscribe(subscription);

    if (context.devices.count == 0 && error != NULL) {
        *error = WMMMakeError(3, @"No connected iPhone or iPad was detected through MobileDevice.framework.");
    }

    return [context.devices copy];
}

static NSString *WMMResolvedDeviceIdentifier(WMMMobileDeviceFunctions *functions, AMDeviceRef device) {
    if (functions->AMDeviceCopyDeviceIdentifier != NULL) {
        CFStringRef copiedIdentifier = functions->AMDeviceCopyDeviceIdentifier(device);
        if (copiedIdentifier != NULL) {
            return CFBridgingRelease(copiedIdentifier);
        }
    }

    return WMMDeviceStringValue(functions, device, CFSTR("UniqueDeviceID")) ?:
        WMMDeviceStringValue(functions, device, CFSTR("SerialNumber")) ?:
        @"";
}

static void WMMReleaseDeviceValues(WMMMobileDeviceFunctions *functions, NSArray<NSValue *> *devices) {
    for (NSValue *value in devices) {
        AMDeviceRef device = (AMDeviceRef)value.pointerValue;
        if (device != NULL) {
            functions->AMDeviceRelease(device);
        }
    }
}

static AMDeviceRef WMMCopyConnectedDevice(
    WMMMobileDeviceFunctions *functions,
    NSString *targetDeviceIdentifier,
    NSError **error
) {
    NSArray<NSValue *> *devices = WMMCopyConnectedDevices(functions, error);
    if (devices.count == 0) {
        return NULL;
    }

    AMDeviceRef matchedDevice = NULL;
    for (NSValue *value in devices) {
        AMDeviceRef device = (AMDeviceRef)value.pointerValue;
        NSString *deviceIdentifier = WMMResolvedDeviceIdentifier(functions, device);
        BOOL matchesTarget = targetDeviceIdentifier.length == 0 || [deviceIdentifier isEqualToString:targetDeviceIdentifier];
        if (!matchesTarget) {
            if (device != NULL) {
                functions->AMDeviceRelease(device);
            }
            continue;
        }

        if (matchedDevice == NULL) {
            matchedDevice = device;
            continue;
        }

        if (WMMConnectionPreferenceRank(device) > WMMConnectionPreferenceRank(matchedDevice)) {
            functions->AMDeviceRelease(matchedDevice);
            matchedDevice = device;
            continue;
        }

        if (device != NULL) {
            functions->AMDeviceRelease(device);
        }
    }

    if (matchedDevice == NULL && error != NULL) {
        *error = WMMMakeError(3, [NSString stringWithFormat:@"The connected device %@ is no longer available.", targetDeviceIdentifier]);
    }

    return matchedDevice;
}

static NSString *WMMDeviceStringValue(WMMMobileDeviceFunctions *functions, AMDeviceRef device, CFStringRef key) {
    if (functions->AMDeviceCopyValue == NULL) {
        return nil;
    }

    CFTypeRef value = functions->AMDeviceCopyValue(device, NULL, key);
    if (value == NULL) {
        return nil;
    }

    if (CFGetTypeID(value) != CFStringGetTypeID()) {
        CFRelease(value);
        return nil;
    }

    return CFBridgingRelease(value);
}

static NSString *WMMInferredConnectionType(AMDeviceRef device) {
    if (device == NULL) {
        return @"USB";
    }

    NSString *deviceDescription = [(__bridge id)device description];
    if (deviceDescription.length == 0) {
        return @"USB";
    }

    if ([deviceDescription containsString:@"FullServiceName = "]) {
        return @"Network";
    }

    if ([deviceDescription containsString:@"location ID = "]) {
        return @"USB";
    }

    return @"USB";
}

static NSInteger WMMConnectionPreferenceRank(AMDeviceRef device) {
    NSString *connectionType = WMMInferredConnectionType(device);
    if ([connectionType caseInsensitiveCompare:@"USB"] == NSOrderedSame) {
        return 2;
    }

    if ([connectionType caseInsensitiveCompare:@"Network"] == NSOrderedSame) {
        return 1;
    }

    return 0;
}

static void WMMLogDeviceTransportDiagnostics(
    WMMMobileDeviceFunctions *functions,
    AMDeviceRef device,
    NSString *resolvedIdentifier
) {
    NSArray<NSString *> *keys = @[
        @"ConnectionType",
        @"InterfaceType",
        @"DeviceName",
        @"ProductType",
        @"ProductVersion",
        @"UniqueDeviceID",
        @"SerialNumber",
        @"WiFiAddress",
        @"EthernetAddress"
    ];

    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *value = WMMDeviceStringValue(functions, device, (__bridge CFStringRef)key);
        values[key] = value.length > 0 ? value : @"<nil>";
    }

    WMMBridgeLog(@"[DeviceSummary] udid=%@ diagnostics=%@", resolvedIdentifier, values);
}

static BOOL WMMConnectAndValidateDevice(
    WMMMobileDeviceFunctions *functions,
    AMDeviceRef device,
    BOOL startSession,
    NSError **error
) {
    const int connectStatus = functions->AMDeviceConnect(device);
    if (connectStatus != 0) {
        if (error != NULL) {
            *error = WMMMakeError(connectStatus, [NSString stringWithFormat:@"AMDeviceConnect failed (%d).", connectStatus]);
        }
        return NO;
    }

    if (!functions->AMDeviceIsPaired(device)) {
        functions->AMDeviceDisconnect(device);
        if (error != NULL) {
            *error = WMMMakeError(5, @"The connected device is not paired with this Mac.");
        }
        return NO;
    }

    const int validateStatus = functions->AMDeviceValidatePairing(device);
    if (validateStatus != 0) {
        functions->AMDeviceDisconnect(device);
        if (error != NULL) {
            *error = WMMMakeError(validateStatus, [NSString stringWithFormat:@"AMDeviceValidatePairing failed (%d).", validateStatus]);
        }
        return NO;
    }

    if (!startSession) {
        return YES;
    }

    const int sessionStatus = functions->AMDeviceStartSession(device);
    if (sessionStatus != 0) {
        functions->AMDeviceDisconnect(device);
        if (error != NULL) {
            *error = WMMMakeError(sessionStatus, [NSString stringWithFormat:@"AMDeviceStartSession failed (%d).", sessionStatus]);
        }
        return NO;
    }

    return YES;
}

static void WMMDisconnectDevice(
    WMMMobileDeviceFunctions *functions,
    AMDeviceRef device,
    BOOL hadSession
) {
    if (hadSession) {
        functions->AMDeviceStopSession(device);
    }

    functions->AMDeviceDisconnect(device);
}

static void WMMCloseVendSession(
    WMMMobileDeviceFunctions *functions,
    AMDeviceRef _Nullable device,
    BOOL hadSession,
    AFCConnectionRef _Nullable afcConnection,
    AMDServiceConnectionRef _Nullable backingServiceConnection
) {
    if (afcConnection != NULL) {
        functions->AFCConnectionClose(afcConnection);
    }

    if (backingServiceConnection != NULL) {
        functions->AMDServiceConnectionInvalidate(backingServiceConnection);
    }

    if (device != NULL) {
        WMMDisconnectDevice(functions, device, hadSession);
    }
}

static AFCConnectionRef _Nullable WMMCreateAFCConnectionFromServiceConnection(
    WMMMobileDeviceFunctions *functions,
    AMDServiceConnectionRef serviceConnection
) {
    int socket = functions->AMDServiceConnectionGetSocket(serviceConnection);
    if (socket < 0) {
        return NULL;
    }

    AFCConnectionRef connection = functions->AFCConnectionCreate(
        kCFAllocatorDefault,
        socket,
        1,
        NULL,
        NULL
    );
    if (connection == NULL) {
        return NULL;
    }

    void *secureContext = functions->AMDServiceConnectionGetSecureIOContext(serviceConnection);
    if (secureContext != NULL) {
        functions->AFCConnectionSetSecureContext(connection, secureContext);
    }

    return connection;
}

static AFCConnectionRef _Nullable WMMCreateVendAFCConnection(
    WMMMobileDeviceFunctions *functions,
    AMDeviceRef device,
    NSString *bundleIdentifier,
    AMDServiceConnectionRef _Nullable * _Nullable backingServiceConnection,
    NSError **error
) {
    if (backingServiceConnection != NULL) {
        *backingServiceConnection = NULL;
    }

    WMMBridgeLog(@"[HouseArrest] Trying AMDeviceCreateHouseArrestService for %@", bundleIdentifier);
    AFCConnectionRef directConnection = NULL;
    int directStatus = functions->AMDeviceCreateHouseArrestService(
        device,
        (__bridge CFStringRef)bundleIdentifier,
        NULL,
        &directConnection
    );
    WMMBridgeLog(@"[HouseArrest] AMDeviceCreateHouseArrestService returned %d connection=%p", directStatus, directConnection);
    if (directStatus == 0 && directConnection != NULL) {
        return directConnection;
    }

    NSArray<NSString *> *commands = @[ @"VendDocuments", @"VendContainer" ];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    [failures addObject:[NSString stringWithFormat:@"AMDeviceCreateHouseArrestService returned %d", directStatus]];

    for (NSString *command in commands) {
        WMMBridgeLog(@"[HouseArrest] Starting %@ for %@", command, bundleIdentifier);
        AMDServiceConnectionRef serviceConnection = NULL;
        int startStatus = functions->AMDeviceSecureStartService(
            device,
            CFSTR("com.apple.mobile.house_arrest"),
            NULL,
            &serviceConnection
        );
        if (startStatus != 0 || serviceConnection == NULL) {
            WMMBridgeLog(@"[HouseArrest] %@ service start failed: %d", command, startStatus);
            [failures addObject:[NSString stringWithFormat:@"%@ service start failed (%d)", command, startStatus]];
            continue;
        }

        int socket = functions->AMDServiceConnectionGetSocket(serviceConnection);
        void *secureContext = functions->AMDServiceConnectionGetSecureIOContext(serviceConnection);
        WMMBridgeLog(@"[HouseArrest] %@ service connection socket=%d secureContext=%p", command, socket, secureContext);

        NSDictionary *request = @{
            @"Command": command,
            @"Identifier": bundleIdentifier
        };

        int sent = functions->AMDServiceConnectionSendMessage(
            serviceConnection,
            (__bridge CFPropertyListRef)request,
            100
        );
        WMMBridgeLog(@"[HouseArrest] %@ send returned %d", command, sent);
        if (sent != 0) {
            [failures addObject:[NSString stringWithFormat:@"%@ request failed to send (%d)", command, sent]];
            functions->AMDServiceConnectionInvalidate(serviceConnection);
            continue;
        }

        CFPropertyListRef response = NULL;
        int received = functions->AMDServiceConnectionReceiveMessage(
            serviceConnection,
            &response,
            0
        );
        WMMBridgeLog(@"[HouseArrest] %@ receive returned %d", command, received);
        if (received != 0 || response == NULL) {
            [failures addObject:[NSString stringWithFormat:@"%@ response could not be read (%d)", command, received]];
            functions->AMDServiceConnectionInvalidate(serviceConnection);
            continue;
        }

        NSDictionary *responseDictionary = CFBridgingRelease(response);
        WMMBridgeLog(@"[HouseArrest] %@ response: %@", command, responseDictionary);
        NSString *status = [responseDictionary isKindOfClass:[NSDictionary class]] ? responseDictionary[@"Status"] : nil;
        if ([status isKindOfClass:[NSString class]] && [status isEqualToString:@"Complete"]) {
            AFCConnectionRef afcConnection = WMMCreateAFCConnectionFromServiceConnection(functions, serviceConnection);
            if (afcConnection != NULL) {
                if (backingServiceConnection != NULL) {
                    *backingServiceConnection = serviceConnection;
                }
                WMMBridgeLog(@"[HouseArrest] %@ completed and AFC initialized", command);
                return afcConnection;
            }

            functions->AMDServiceConnectionInvalidate(serviceConnection);
            WMMBridgeLog(@"[HouseArrest] %@ completed but AFC initialization failed", command);
            [failures addObject:[NSString stringWithFormat:@"%@ succeeded but AFC initialization failed", command]];
            break;
        }

        NSString *serviceError = [responseDictionary isKindOfClass:[NSDictionary class]] ? responseDictionary[@"Error"] : nil;
        if ([serviceError isKindOfClass:[NSString class]] && serviceError.length > 0) {
            WMMBridgeLog(@"[HouseArrest] %@ rejected with error: %@", command, serviceError);
            [failures addObject:[NSString stringWithFormat:@"%@ was rejected: %@", command, serviceError]];
        } else {
            WMMBridgeLog(@"[HouseArrest] %@ did not complete", command);
            [failures addObject:[NSString stringWithFormat:@"%@ did not complete", command]];
        }
        functions->AMDServiceConnectionInvalidate(serviceConnection);
    }

    if (error != NULL) {
        NSString *failureSummary = failures.count > 0
            ? [failures componentsJoinedByString:@"; "]
            : @"House Arrest vend request failed.";
        *error = WMMMakeError(11, failureSummary);
    }
    return NULL;
}

static int WMMReadAFCDirectory(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *path,
    NSMutableArray<NSString *> **entriesOut
) {
    NSString *effectivePath = path;
    if (effectivePath.length == 0) {
        effectivePath = @".";
    }

    AFCDirectoryRef directory = NULL;
    const int openDirectoryStatus = functions->AFCDirectoryOpen(
        afcConnection,
        effectivePath.fileSystemRepresentation,
        &directory
    );
    if (openDirectoryStatus != 0 || directory == NULL) {
        return openDirectoryStatus != 0 ? openDirectoryStatus : -1;
    }

    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    int result = 0;
    while (true) {
        char *entry = NULL;
        const int readStatus = functions->AFCDirectoryRead(afcConnection, directory, &entry);
        if (readStatus != 0) {
            result = readStatus;
            break;
        }

        if (entry == NULL) {
            break;
        }

        NSString *entryName = [NSString stringWithUTF8String:entry];
        if (entryName.length > 0) {
            [entries addObject:entryName];
        }
    }

    functions->AFCDirectoryClose(afcConnection, directory);
    if (result == 0 && entriesOut != NULL) {
        *entriesOut = entries;
    }
    return result;
}

static NSDictionary<NSString *, NSString *> * _Nullable WMMCopyAFCFileInfo(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *path,
    NSError **error
) {
    AFCIteratorRef iterator = NULL;
    const int openStatus = functions->AFCFileInfoOpen(
        afcConnection,
        path.fileSystemRepresentation,
        &iterator
    );
    if (openStatus != 0 || iterator == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(openStatus, [NSString stringWithFormat:@"AFCFileInfoOpen failed for %@ (%d).", path, openStatus]);
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *info = [NSMutableDictionary dictionary];
    while (true) {
        char *key = NULL;
        char *value = NULL;
        const int readStatus = functions->AFCKeyValueRead(iterator, &key, &value);
        if (readStatus != 0) {
            functions->AFCKeyValueClose(iterator);
            if (error != NULL) {
                *error = WMMMakeError(readStatus, [NSString stringWithFormat:@"AFCKeyValueRead failed for %@ (%d).", path, readStatus]);
            }
            return nil;
        }

        if (key == NULL || value == NULL) {
            break;
        }

        NSString *keyString = [NSString stringWithUTF8String:key];
        NSString *valueString = [NSString stringWithUTF8String:value];
        if (keyString.length > 0 && valueString.length > 0) {
            info[keyString] = valueString;
        }
    }

    functions->AFCKeyValueClose(iterator);
    return info;
}

static unsigned long long WMMParseUnsignedLongLong(NSString *value) {
    if (value.length == 0) {
        return 0;
    }

    NSScanner *hexScanner = [NSScanner scannerWithString:value];
    unsigned long long hexValue = 0;
    if (([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"])
        && [hexScanner scanString:@"0x" intoString:nil]
        && [hexScanner scanHexLongLong:&hexValue]) {
        return hexValue;
    }

    return strtoull(value.UTF8String, NULL, 10);
}

static NSDate * _Nullable WMMDateFromAFCTimestampString(NSString *value) {
    unsigned long long rawValue = WMMParseUnsignedLongLong(value);
    if (rawValue == 0) {
        return nil;
    }

    NSTimeInterval seconds;
    if (rawValue > 10000000000000000ULL) {
        seconds = (NSTimeInterval)rawValue / 1000000000.0;
    } else if (rawValue > 10000000000000ULL) {
        seconds = (NSTimeInterval)rawValue / 1000000.0;
    } else if (rawValue > 10000000000ULL) {
        seconds = (NSTimeInterval)rawValue / 1000.0;
    } else {
        seconds = (NSTimeInterval)rawValue;
    }

    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

static NSDate * _Nullable WMMModificationDateFromAFCInfo(NSDictionary<NSString *, NSString *> *info) {
    NSString *candidate = info[@"st_mtime"] ?: info[@"st_birthtime"];
    if (candidate.length == 0) {
        return nil;
    }

    return WMMDateFromAFCTimestampString(candidate);
}

static long long WMMFileSizeFromAFCInfo(NSDictionary<NSString *, NSString *> *info) {
    NSString *candidate = info[@"st_size"];
    if (candidate.length == 0) {
        return 0;
    }

    unsigned long long parsed = WMMParseUnsignedLongLong(candidate);
    if (parsed > LLONG_MAX) {
        return LLONG_MAX;
    }

    return (long long)parsed;
}

static NSDictionary<NSString *, id> * _Nullable WMMCopyAFCTreeMetrics(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSError **error
) {
    NSDictionary<NSString *, NSString *> *info = WMMCopyAFCFileInfo(functions, afcConnection, remotePath, error);
    if (info == nil) {
        return nil;
    }

    NSDate *latestModificationDate = WMMModificationDateFromAFCInfo(info);
    NSMutableArray<NSString *> *entries = nil;
    const int directoryStatus = WMMReadAFCDirectory(functions, afcConnection, remotePath, &entries);
    if (directoryStatus != 0) {
        return @{
            @"sizeBytes": @(WMMFileSizeFromAFCInfo(info)),
            @"modifiedDate": latestModificationDate ?: [NSNull null]
        };
    }

    long long totalSize = 0;
    for (NSString *entry in entries) {
        if ([entry isEqualToString:@"."] || [entry isEqualToString:@".."]) {
            continue;
        }

        NSString *childRemotePath = [remotePath hasSuffix:@"/"]
            ? [remotePath stringByAppendingString:entry]
            : [remotePath stringByAppendingPathComponent:entry];
        NSDictionary<NSString *, id> *childMetrics = WMMCopyAFCTreeMetrics(
            functions,
            afcConnection,
            childRemotePath,
            error
        );
        if (childMetrics == nil) {
            return nil;
        }

        totalSize += [childMetrics[@"sizeBytes"] longLongValue];
        NSDate *childModifiedDate = childMetrics[@"modifiedDate"];
        if ([childModifiedDate isKindOfClass:[NSDate class]]
            && (latestModificationDate == nil || [childModifiedDate compare:latestModificationDate] == NSOrderedDescending)) {
            latestModificationDate = childModifiedDate;
        }
    }

    return @{
        @"sizeBytes": @(totalSize),
        @"modifiedDate": latestModificationDate ?: [NSNull null]
    };
}

static BOOL WMMCopyAFCFileToLocalURL(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSURL *localFileURL,
    NSError **error
) {
    AFCFileDescriptorRef fileDescriptor = NULL;
    const int openStatus = functions->AFCFileRefOpen(
        afcConnection,
        remotePath.fileSystemRepresentation,
        1,
        &fileDescriptor
    );
    if (openStatus != 0 || fileDescriptor == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(openStatus, [NSString stringWithFormat:@"AFCFileRefOpen failed for %@ (%d).", remotePath, openStatus]);
        }
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createFileAtPath:localFileURL.path contents:nil attributes:nil];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:localFileURL error:error];
    if (handle == nil) {
        if (error != NULL && *error != nil) {
            *error = [NSError errorWithDomain:(*error).domain code:(*error).code userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open local file %@ for remote AFC path %@: %@",
                    localFileURL.path,
                    remotePath,
                    (*error).localizedDescription]
            }];
        }
        functions->AFCFileRefClose(afcConnection, fileDescriptor);
        return NO;
    }

    BOOL success = YES;
    NSMutableData *buffer = [NSMutableData dataWithLength:64 * 1024];
    while (true) {
        size_t bytesToRead = buffer.length;
        const int readStatus = functions->AFCFileRefRead(
            afcConnection,
            fileDescriptor,
            buffer.mutableBytes,
            &bytesToRead
        );
        if (readStatus != 0) {
            if (error != NULL) {
                *error = WMMMakeError(readStatus, [NSString stringWithFormat:@"AFCFileRefRead failed for %@ (%d).", remotePath, readStatus]);
            }
            success = NO;
            break;
        }

        if (bytesToRead == 0) {
            break;
        }

        NSData *chunk = [NSData dataWithBytes:buffer.bytes length:bytesToRead];
        if (![handle writeData:chunk error:error]) {
            if (error != NULL && *error != nil) {
                *error = [NSError errorWithDomain:(*error).domain code:(*error).code userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed writing local file %@ for remote AFC path %@: %@",
                        localFileURL.path,
                        remotePath,
                        (*error).localizedDescription]
                }];
            }
            success = NO;
            break;
        }
    }

    [handle closeFile];
    functions->AFCFileRefClose(afcConnection, fileDescriptor);
    return success;
}

static BOOL WMMCopyAFCTreeToLocalURL(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSURL *localURL,
    NSError **error
) {
    NSMutableArray<NSString *> *entries = nil;
    const int directoryStatus = WMMReadAFCDirectory(functions, afcConnection, remotePath, &entries);
    if (directoryStatus == 0) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager createDirectoryAtURL:localURL withIntermediateDirectories:YES attributes:nil error:error]) {
            if (error != NULL && *error != nil) {
                *error = [NSError errorWithDomain:(*error).domain code:(*error).code userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create local directory %@ for remote AFC path %@: %@",
                        localURL.path,
                        remotePath,
                        (*error).localizedDescription]
                }];
            }
            return NO;
        }

        for (NSString *entry in entries) {
            if ([entry isEqualToString:@"."] || [entry isEqualToString:@".."]) {
                continue;
            }

            NSString *childRemotePath = remotePath;
            if ([childRemotePath hasSuffix:@"/"]) {
                childRemotePath = [childRemotePath stringByAppendingString:entry];
            } else {
                childRemotePath = [childRemotePath stringByAppendingPathComponent:entry];
            }
            NSURL *childLocalURL = [localURL URLByAppendingPathComponent:entry];
            if (!WMMCopyAFCTreeToLocalURL(functions, afcConnection, childRemotePath, childLocalURL, error)) {
                if (error != NULL && *error != nil) {
                    *error = [NSError errorWithDomain:(*error).domain code:(*error).code userInfo:@{
                        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed copying remote AFC path %@ into %@: %@",
                            childRemotePath,
                            childLocalURL.path,
                            (*error).localizedDescription]
                    }];
                }
                return NO;
            }
        }

        return YES;
    }

    return WMMCopyAFCFileToLocalURL(functions, afcConnection, remotePath, localURL, error);
}

static BOOL WMMEnsureAFCDirectory(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSError **error
) {
    NSMutableArray<NSString *> *existingEntries = nil;
    if (WMMReadAFCDirectory(functions, afcConnection, remotePath, &existingEntries) == 0) {
        return YES;
    }

    const int createStatus = functions->AFCDirectoryCreate(
        afcConnection,
        remotePath.fileSystemRepresentation
    );
    if (createStatus != 0) {
        if (error != NULL) {
            *error = WMMMakeError(
                createStatus,
                [NSString stringWithFormat:@"AFCDirectoryCreate failed for %@ (%d).", remotePath, createStatus]
            );
        }
        return NO;
    }
    return YES;
}

static BOOL WMMCopyLocalFileToAFCPath(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSURL *localFileURL,
    NSString *remotePath,
    NSError **error
) {
    AFCFileDescriptorRef fileDescriptor = NULL;
    const int openStatus = functions->AFCFileRefOpen(
        afcConnection,
        remotePath.fileSystemRepresentation,
        3,
        &fileDescriptor
    );
    if (openStatus != 0 || fileDescriptor == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(
                openStatus,
                [NSString stringWithFormat:@"AFCFileRefOpen for writing failed for %@ (%d).", remotePath, openStatus]
            );
        }
        return NO;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:localFileURL error:error];
    if (handle == nil) {
        functions->AFCFileRefClose(afcConnection, fileDescriptor);
        return NO;
    }

    BOOL success = YES;
    while (true) {
        @autoreleasepool {
            NSData *chunk = [handle readDataOfLength:64 * 1024];
            if (chunk.length == 0) {
                break;
            }
            const int writeStatus = functions->AFCFileRefWrite(
                afcConnection,
                fileDescriptor,
                chunk.bytes,
                (uint32_t)chunk.length
            );
            if (writeStatus != 0) {
                if (error != NULL) {
                    *error = WMMMakeError(
                        writeStatus,
                        [NSString stringWithFormat:@"AFCFileRefWrite failed for %@ (%d).", remotePath, writeStatus]
                    );
                }
                success = NO;
                break;
            }
        }
    }

    [handle closeFile];
    functions->AFCFileRefClose(afcConnection, fileDescriptor);
    return success;
}

static BOOL WMMCopyLocalTreeToAFCPath(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSURL *localURL,
    NSString *remotePath,
    NSError **error
) {
    NSNumber *isDirectory = nil;
    if (![localURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:error]) {
        return NO;
    }

    if (!isDirectory.boolValue) {
        return WMMCopyLocalFileToAFCPath(functions, afcConnection, localURL, remotePath, error);
    }

    if (!WMMEnsureAFCDirectory(functions, afcConnection, remotePath, error)) {
        return NO;
    }

    NSArray<NSURL *> *children = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:localURL
                                                              includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey]
                                                                                 options:0
                                                                                   error:error];
    if (children == nil) {
        return NO;
    }

    for (NSURL *childURL in children) {
        NSNumber *isSymbolicLink = nil;
        if (![childURL getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:error]) {
            return NO;
        }
        if (isSymbolicLink.boolValue) {
            if (error != NULL) {
                *error = WMMMakeError(17, [NSString stringWithFormat:@"Symbolic links cannot be installed: %@", childURL.path]);
            }
            return NO;
        }

        NSString *childRemotePath = [remotePath stringByAppendingPathComponent:childURL.lastPathComponent];
        if (!WMMCopyLocalTreeToAFCPath(functions, afcConnection, childURL, childRemotePath, error)) {
            return NO;
        }
    }
    return YES;
}

static BOOL WMMRemoveAFCTree(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath
) {
    NSMutableArray<NSString *> *entries = nil;
    if (WMMReadAFCDirectory(functions, afcConnection, remotePath, &entries) == 0) {
        for (NSString *entry in entries) {
            if ([entry isEqualToString:@"."] || [entry isEqualToString:@".."]) {
                continue;
            }
            WMMRemoveAFCTree(
                functions,
                afcConnection,
                [remotePath stringByAppendingPathComponent:entry]
            );
        }
    }
    return functions->AFCRemovePath(afcConnection, remotePath.fileSystemRepresentation) == 0;
}

static NSString *WMMNormalizedAFCPath(NSString *path) {
    NSString *normalizedPath = path.length == 0 ? @"/" : path;
    if (![normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [@"/" stringByAppendingString:normalizedPath];
    }
    return normalizedPath;
}

static NSData * _Nullable WMMCopyAFCFileData(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSError **error
) {
    AFCFileDescriptorRef fileDescriptor = NULL;
    const int openStatus = functions->AFCFileRefOpen(
        afcConnection,
        remotePath.fileSystemRepresentation,
        1,
        &fileDescriptor
    );
    if (openStatus != 0 || fileDescriptor == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(openStatus, [NSString stringWithFormat:@"AFCFileRefOpen failed for %@ (%d).", remotePath, openStatus]);
        }
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    NSMutableData *buffer = [NSMutableData dataWithLength:64 * 1024];
    while (true) {
        size_t bytesToRead = buffer.length;
        const int readStatus = functions->AFCFileRefRead(
            afcConnection,
            fileDescriptor,
            buffer.mutableBytes,
            &bytesToRead
        );
        if (readStatus != 0) {
            if (error != NULL) {
                *error = WMMMakeError(readStatus, [NSString stringWithFormat:@"AFCFileRefRead failed for %@ (%d).", remotePath, readStatus]);
            }
            functions->AFCFileRefClose(afcConnection, fileDescriptor);
            return nil;
        }

        if (bytesToRead == 0) {
            break;
        }

        [data appendBytes:buffer.bytes length:bytesToRead];
    }

    functions->AFCFileRefClose(afcConnection, fileDescriptor);
    return data;
}

static BOOL WMMEntryArrayContainsName(NSArray<NSString *> *entries, NSString *candidate) {
    for (NSString *entry in entries) {
        if ([entry isEqualToString:candidate]) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *WMMIconCandidateFileNamesForContentType(NSString *contentType) {
    if ([contentType isEqualToString:@"World"]) {
        return @[ @"world_icon.jpeg", @"world_icon.jpg", @"world_icon.png" ];
    }

    return @[ @"pack_icon.png", @"pack_icon.jpeg", @"pack_icon.jpg" ];
}

static NSString * _Nullable WMMReadUTF8TextFile(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath
) {
    NSData *data = WMMCopyAFCFileData(functions, afcConnection, remotePath, NULL);
    if (data == nil) {
        return nil;
    }

    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSDictionary<NSString *, id> * _Nullable WMMReadManifestHeader(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath
) {
    NSData *data = WMMCopyAFCFileData(functions, afcConnection, remotePath, NULL);
    if (data == nil) {
        return nil;
    }

    NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *header = jsonObject[@"header"];
    if (![header isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return header;
}

static NSString * _Nullable WMMVersionStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return stringValue.length > 0 ? stringValue : nil;
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *components = [NSMutableArray array];
        for (id component in (NSArray *)value) {
            if ([component isKindOfClass:[NSNumber class]]) {
                [components addObject:[(NSNumber *)component stringValue]];
            } else if ([component isKindOfClass:[NSString class]]) {
                [components addObject:(NSString *)component];
            }
        }
        return components.count > 0 ? [components componentsJoinedByString:@"."] : nil;
    }

    return nil;
}

static NSDictionary<NSString *, id> *WMMBuildPackReferenceSummary(
    NSString *name,
    NSString *contentType,
    NSString * _Nullable uuid,
    NSString * _Nullable version,
    NSString *source
) {
    NSMutableDictionary<NSString *, id> *summary = [@{
        @"name": name,
        @"contentType": contentType,
        @"source": source
    } mutableCopy];

    if (uuid.length > 0) {
        summary[@"uuid"] = [uuid lowercaseString];
    }

    if (version.length > 0) {
        summary[@"version"] = version;
    }

    return summary;
}

static NSArray<NSDictionary<NSString *, id> *> *WMMParsePackReferenceSummariesFromData(
    NSData *data,
    NSString *contentType
) {
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![jsonObject isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *references = [NSMutableArray array];
    for (id entry in (NSArray *)jsonObject) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *entryDictionary = (NSDictionary *)entry;
        NSString *uuid = [entryDictionary[@"pack_id"] isKindOfClass:[NSString class]] ? entryDictionary[@"pack_id"] : nil;
        NSString *version = WMMVersionStringFromValue(entryDictionary[@"version"]);
        NSString *name = uuid.length > 0 ? uuid : @"Referenced Pack";
        [references addObject:WMMBuildPackReferenceSummary(
            name,
            contentType,
            uuid,
            version,
            @"referencedByWorld"
        )];
    }

    return references;
}

static NSArray<NSDictionary<NSString *, id> *> *WMMReadPackReferenceSummariesFile(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remotePath,
    NSString *contentType
) {
    NSData *data = WMMCopyAFCFileData(functions, afcConnection, remotePath, NULL);
    if (data == nil) {
        return @[];
    }

    return WMMParsePackReferenceSummariesFromData(data, contentType);
}

static NSArray<NSDictionary<NSString *, id> *> *WMMLoadEmbeddedPackReferenceSummaries(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *remoteFolderPath,
    NSString *contentType
) {
    NSMutableArray<NSString *> *childFolders = nil;
    if (WMMReadAFCDirectory(functions, afcConnection, remoteFolderPath, &childFolders) != 0 || childFolders == nil) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *references = [NSMutableArray array];
    for (NSString *childFolder in childFolders) {
        if ([childFolder isEqualToString:@"."] || [childFolder isEqualToString:@".."]) {
            continue;
        }

        NSString *manifestPath = [[remoteFolderPath stringByAppendingPathComponent:childFolder] stringByAppendingPathComponent:@"manifest.json"];
        NSDictionary<NSString *, id> *header = WMMReadManifestHeader(functions, afcConnection, manifestPath);
        if (header == nil) {
            continue;
        }

        NSString *name = [header[@"name"] isKindOfClass:[NSString class]] && [header[@"name"] length] > 0
            ? header[@"name"]
            : childFolder;
        NSString *uuid = [header[@"uuid"] isKindOfClass:[NSString class]] ? header[@"uuid"] : nil;
        NSString *version = WMMVersionStringFromValue(header[@"version"]);
        [references addObject:WMMBuildPackReferenceSummary(
            name,
            contentType,
            uuid,
            version,
            @"embeddedInWorld"
        )];
    }

    return references;
}

static BOOL WMMIsCandidateItem(NSString *contentType, NSArray<NSString *> *entries) {
    if ([contentType isEqualToString:@"World"]) {
        return WMMEntryArrayContainsName(entries, @"level.dat")
            || WMMEntryArrayContainsName(entries, @"db")
            || WMMEntryArrayContainsName(entries, @"levelname.txt");
    }

    return WMMEntryArrayContainsName(entries, @"manifest.json")
        || WMMEntryArrayContainsName(entries, @"pack_icon.png")
        || WMMEntryArrayContainsName(entries, @"pack_icon.jpeg")
        || WMMEntryArrayContainsName(entries, @"pack_icon.jpg");
}

static NSDictionary<NSString *, id> *WMMBuildShallowMinecraftItemSummary(
    NSString *contentType,
    NSString *collectionFolderName,
    NSString *itemRelativePath,
    NSString *folderName,
    NSArray<NSString *> *entries
) {
    NSMutableDictionary<NSString *, id> *summary = [@{
        @"contentType": contentType,
        @"collectionFolderName": collectionFolderName,
        @"relativePath": itemRelativePath,
        @"folderName": folderName,
        @"displayName": folderName
    } mutableCopy];
    summary[@"hasIcon"] = @(
        WMMEntryArrayContainsName(entries, @"world_icon.png")
            || WMMEntryArrayContainsName(entries, @"world_icon.jpeg")
            || WMMEntryArrayContainsName(entries, @"world_icon.jpg")
            || WMMEntryArrayContainsName(entries, @"pack_icon.png")
            || WMMEntryArrayContainsName(entries, @"pack_icon.jpeg")
            || WMMEntryArrayContainsName(entries, @"pack_icon.jpg")
    );
    return summary;
}

static void WMMAppendCollectionSummaries(
    WMMMobileDeviceFunctions *functions,
    AFCConnectionRef afcConnection,
    NSString *rootRemotePath,
    NSString *collectionFolderName,
    NSString *contentType,
    NSMutableArray<NSDictionary<NSString *, id> *> *results
) {
    NSString *collectionRemotePath = [rootRemotePath stringByAppendingPathComponent:collectionFolderName];
    NSMutableArray<NSString *> *itemFolderNames = nil;
    if (WMMReadAFCDirectory(functions, afcConnection, collectionRemotePath, &itemFolderNames) != 0 || itemFolderNames == nil) {
        return;
    }

    for (NSString *itemFolderName in itemFolderNames) {
        if ([itemFolderName isEqualToString:@"."] || [itemFolderName isEqualToString:@".."]) {
            continue;
        }

        NSString *itemRemotePath = [collectionRemotePath stringByAppendingPathComponent:itemFolderName];
        NSMutableArray<NSString *> *itemEntries = nil;
        if (WMMReadAFCDirectory(functions, afcConnection, itemRemotePath, &itemEntries) != 0 || itemEntries == nil) {
            continue;
        }

        if (!WMMIsCandidateItem(contentType, itemEntries)) {
            continue;
        }

        NSString *itemRelativePath = [collectionFolderName stringByAppendingPathComponent:itemFolderName];
        [results addObject:WMMBuildShallowMinecraftItemSummary(
            contentType,
            collectionFolderName,
            itemRelativePath,
            itemFolderName,
            itemEntries
        )];

        if (![contentType isEqualToString:@"World"]) {
            continue;
        }

        NSArray<NSDictionary<NSString *, NSString *> *> *embeddedCollections = @[
            @{ @"folder": @"behavior_packs", @"type": @"Behavior Pack" },
            @{ @"folder": @"resource_packs", @"type": @"Resource Pack" }
        ];

        for (NSDictionary<NSString *, NSString *> *embeddedCollection in embeddedCollections) {
            NSString *embeddedFolder = embeddedCollection[@"folder"];
            NSString *embeddedType = embeddedCollection[@"type"];
            NSString *embeddedCollectionPath = [itemRemotePath stringByAppendingPathComponent:embeddedFolder];
            NSMutableArray<NSString *> *embeddedFolderNames = nil;
            if (WMMReadAFCDirectory(functions, afcConnection, embeddedCollectionPath, &embeddedFolderNames) != 0 || embeddedFolderNames == nil) {
                continue;
            }

            for (NSString *embeddedFolderName in embeddedFolderNames) {
                if ([embeddedFolderName isEqualToString:@"."] || [embeddedFolderName isEqualToString:@".."]) {
                    continue;
                }

                NSString *embeddedItemPath = [embeddedCollectionPath stringByAppendingPathComponent:embeddedFolderName];
                NSMutableArray<NSString *> *embeddedEntries = nil;
                if (WMMReadAFCDirectory(functions, afcConnection, embeddedItemPath, &embeddedEntries) != 0 || embeddedEntries == nil) {
                    continue;
                }

                if (!WMMIsCandidateItem(embeddedType, embeddedEntries)) {
                    continue;
                }

                NSString *embeddedRelativePath = [itemRelativePath stringByAppendingPathComponent:[embeddedFolder stringByAppendingPathComponent:embeddedFolderName]];
                [results addObject:WMMBuildShallowMinecraftItemSummary(
                    embeddedType,
                    embeddedFolder,
                    embeddedRelativePath,
                    embeddedFolderName,
                    embeddedEntries
                )];
            }
        }
    }
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceSummaries(NSError **error) {
    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    NSArray<NSValue *> *devices = WMMCopyConnectedDevices(&functions, error);
    if (devices.count == 0) {
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *summaries = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSValue *> *preferredDevicesByIdentifier = [NSMutableDictionary dictionary];
    for (NSValue *value in devices) {
        AMDeviceRef device = (AMDeviceRef)value.pointerValue;
        if (device == NULL) {
            continue;
        }

        NSString *deviceIdentifier = WMMResolvedDeviceIdentifier(&functions, device);
        if (deviceIdentifier.length == 0) {
            continue;
        }

        NSValue *existingValue = preferredDevicesByIdentifier[deviceIdentifier];
        AMDeviceRef existingDevice = existingValue != nil ? (AMDeviceRef)existingValue.pointerValue : NULL;
        if (existingDevice != NULL && WMMConnectionPreferenceRank(device) <= WMMConnectionPreferenceRank(existingDevice)) {
            continue;
        }
        preferredDevicesByIdentifier[deviceIdentifier] = value;
    }

    for (NSString *deviceIdentifier in preferredDevicesByIdentifier) {
        AMDeviceRef device = (AMDeviceRef)preferredDevicesByIdentifier[deviceIdentifier].pointerValue;
        if (device == NULL) {
            continue;
        }
        NSString *deviceName = @"Unknown Device";
        NSString *productType = @"";
        NSString *productVersion = @"";
        NSString *connectionType = WMMDeviceStringValue(&functions, device, CFSTR("ConnectionType")) ?: WMMInferredConnectionType(device);
        if (WMMConnectAndValidateDevice(&functions, device, NO, NULL)) {
            deviceName = WMMDeviceStringValue(&functions, device, CFSTR("DeviceName")) ?: @"Unknown Device";
            productType = WMMDeviceStringValue(&functions, device, CFSTR("ProductType")) ?: @"";
            productVersion = WMMDeviceStringValue(&functions, device, CFSTR("ProductVersion")) ?: @"";
            connectionType = WMMDeviceStringValue(&functions, device, CFSTR("ConnectionType")) ?: WMMInferredConnectionType(device);
            WMMLogDeviceTransportDiagnostics(&functions, device, deviceIdentifier);
            WMMDisconnectDevice(&functions, device, NO);
        }

        [summaries addObject:@{
            @"deviceName": deviceName,
            @"deviceIdentifier": deviceIdentifier,
            @"productType": productType,
            @"productVersion": productVersion,
            @"connectionType": connectionType,
            @"trustState": @"trusted"
        }];
    }

    WMMReleaseDeviceValues(&functions, devices);

    [summaries sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs, NSDictionary<NSString *, id> *rhs) {
        return [lhs[@"deviceName"] localizedStandardCompare:rhs[@"deviceName"]];
    }];

    return @{ @"devices": summaries };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppDirectoryListing(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(4, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *deviceName = WMMDeviceStringValue(&functions, device, CFSTR("DeviceName")) ?: @"Unknown Device";
    NSString *productType = WMMDeviceStringValue(&functions, device, CFSTR("ProductType")) ?: @"";
    NSString *productVersion = WMMDeviceStringValue(&functions, device, CFSTR("ProductVersion")) ?: @"";
    NSString *resolvedDeviceIdentifier = WMMResolvedDeviceIdentifier(&functions, device);

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedPath = relativePath.length == 0 ? @"/" : relativePath;
    if (![normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [@"/" stringByAppendingString:normalizedPath];
    }

    NSMutableArray<NSString *> *entries = nil;
    const int directoryStatus = WMMReadAFCDirectory(&functions, afcConnection, normalizedPath, &entries);
    if (directoryStatus != 0) {
        NSMutableArray<NSString *> *rootEntries = nil;
        const int rootStatus = WMMReadAFCDirectory(&functions, afcConnection, @"/", &rootEntries);

        WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
        functions.AMDeviceRelease(device);
        if (error != NULL) {
            NSString *message = [NSString stringWithFormat:@"AFC directory read failed for %@ (%d).", normalizedPath, directoryStatus];
            if (rootStatus == 0 && rootEntries.count > 0) {
                NSString *rootSummary = [rootEntries componentsJoinedByString:@", "];
                message = [message stringByAppendingFormat:@" Vend root contains: %@.", rootSummary];
            } else if (rootStatus != 0) {
                message = [message stringByAppendingFormat:@" Vend root listing also failed (%d).", rootStatus];
            }
            *error = WMMMakeError(directoryStatus, message);
        }
        return nil;
    }
    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);

    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"path": normalizedPath,
        @"deviceName": deviceName,
        @"deviceIdentifier": resolvedDeviceIdentifier,
        @"productType": productType,
        @"productVersion": productVersion,
        @"entries": entries
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathProbeResults(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSArray<NSString *> *paths,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(4, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *deviceName = WMMDeviceStringValue(&functions, device, CFSTR("DeviceName")) ?: @"Unknown Device";
    NSString *productType = WMMDeviceStringValue(&functions, device, CFSTR("ProductType")) ?: @"";
    NSString *productVersion = WMMDeviceStringValue(&functions, device, CFSTR("ProductVersion")) ?: @"";
    NSString *resolvedDeviceIdentifier = WMMResolvedDeviceIdentifier(&functions, device);

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
    for (NSString *candidate in paths) {
        if (![candidate isKindOfClass:[NSString class]]) {
            continue;
        }

        NSMutableArray<NSString *> *entries = nil;
        int status = WMMReadAFCDirectory(&functions, afcConnection, candidate, &entries);

        NSMutableDictionary<NSString *, id> *result = [@{
            @"path": candidate,
            @"status": @(status),
            @"success": @(status == 0)
        } mutableCopy];
        if (status == 0 && entries != nil) {
            result[@"entries"] = entries;
        }

        [results addObject:result];
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"deviceName": deviceName,
        @"deviceIdentifier": resolvedDeviceIdentifier,
        @"productType": productType,
        @"productVersion": productVersion,
        @"results": results
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceApplicationList(
    NSString *deviceIdentifier,
    NSError **error
) {
    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *deviceName = WMMDeviceStringValue(&functions, device, CFSTR("DeviceName")) ?: @"Unknown Device";
    NSString *productType = WMMDeviceStringValue(&functions, device, CFSTR("ProductType")) ?: @"";
    NSString *productVersion = WMMDeviceStringValue(&functions, device, CFSTR("ProductVersion")) ?: @"";
    NSString *resolvedDeviceIdentifier = WMMResolvedDeviceIdentifier(&functions, device);

    CFDictionaryRef appDictionary = NULL;
    const int lookupStatus = functions.AMDeviceLookupApplications(device, NULL, &appDictionary);
    WMMDisconnectDevice(&functions, device, YES);
    functions.AMDeviceRelease(device);

    if (lookupStatus != 0 || appDictionary == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(lookupStatus, [NSString stringWithFormat:@"AMDeviceLookupApplications failed (%d).", lookupStatus]);
        }
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *applications = [NSMutableArray array];
    NSDictionary *bridgedApps = CFBridgingRelease(appDictionary);
    [bridgedApps enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:[NSString class]]) {
            return;
        }

        NSString *bundleIdentifier = (NSString *)key;
        NSString *displayName = bundleIdentifier;

        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *appInfo = (NSDictionary *)obj;
            NSString *candidateName = appInfo[@"CFBundleDisplayName"];
            if (![candidateName isKindOfClass:[NSString class]] || candidateName.length == 0) {
                candidateName = appInfo[@"CFBundleName"];
            }
            if (![candidateName isKindOfClass:[NSString class]] || candidateName.length == 0) {
                candidateName = appInfo[@"Path"];
            }
            if ([candidateName isKindOfClass:[NSString class]] && candidateName.length > 0) {
                displayName = candidateName;
            }
        }

        NSNumber *uiFileSharingEnabled = @NO;
        NSNumber *supportsOpeningDocumentsInPlace = @NO;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *appInfo = (NSDictionary *)obj;
            id fileSharingValue = appInfo[@"UIFileSharingEnabled"];
            if ([fileSharingValue isKindOfClass:[NSNumber class]]) {
                uiFileSharingEnabled = fileSharingValue;
            }

            id openingInPlaceValue = appInfo[@"LSSupportsOpeningDocumentsInPlace"];
            if ([openingInPlaceValue isKindOfClass:[NSNumber class]]) {
                supportsOpeningDocumentsInPlace = openingInPlaceValue;
            }
        }

        [applications addObject:@{
            @"bundleIdentifier": bundleIdentifier,
            @"displayName": displayName,
            @"uiFileSharingEnabled": uiFileSharingEnabled,
            @"supportsOpeningDocumentsInPlace": supportsOpeningDocumentsInPlace
        }];
    }];

    [applications sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *lhs, NSDictionary<NSString *, id> *rhs) {
        return [lhs[@"displayName"] localizedStandardCompare:rhs[@"displayName"]];
    }];

    return @{
        @"deviceName": deviceName,
        @"deviceIdentifier": resolvedDeviceIdentifier,
        @"productType": productType,
        @"productVersion": productVersion,
        @"applications": applications
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftLibrarySnapshot(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(16, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedRootPath = WMMNormalizedAFCPath(relativePath);
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];
    NSArray<NSDictionary<NSString *, NSString *> *> *collections = @[
        @{ @"folder": @"minecraftWorlds", @"type": @"World" },
        @{ @"folder": @"behavior_packs", @"type": @"Behavior Pack" },
        @{ @"folder": @"resource_packs", @"type": @"Resource Pack" },
        @{ @"folder": @"skin_packs", @"type": @"Skin Pack" },
        @{ @"folder": @"world_templates", @"type": @"World Template" }
    ];

    for (NSDictionary<NSString *, NSString *> *collection in collections) {
        WMMAppendCollectionSummaries(
            &functions,
            afcConnection,
            normalizedRootPath,
            collection[@"folder"],
            collection[@"type"],
            items
        );
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"path": normalizedRootPath,
        @"items": items
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftMetadataBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSArray<NSDictionary<NSString *, id> *> *items,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(19, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedRootPath = WMMNormalizedAFCPath(relativePath);
    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];

    for (NSDictionary<NSString *, id> *item in items) {
        NSString *contentType = [item[@"contentType"] isKindOfClass:[NSString class]] ? item[@"contentType"] : nil;
        NSString *relativeItemPath = [item[@"relativePath"] isKindOfClass:[NSString class]] ? item[@"relativePath"] : nil;
        NSString *folderName = [item[@"folderName"] isKindOfClass:[NSString class]] ? item[@"folderName"] : nil;
        if (contentType.length == 0 || relativeItemPath.length == 0 || folderName.length == 0) {
            continue;
        }

        NSString *itemRemotePath = [normalizedRootPath stringByAppendingPathComponent:relativeItemPath];
        NSMutableDictionary<NSString *, id> *metadata = [@{
            @"relativePath": relativeItemPath
        } mutableCopy];

        if ([contentType isEqualToString:@"World"]) {
            NSString *levelName = WMMReadUTF8TextFile(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"levelname.txt"]
            );
            metadata[@"displayName"] = levelName.length > 0 ? levelName : folderName;

            NSMutableArray<NSDictionary<NSString *, id> *> *packReferences = [NSMutableArray array];
            [packReferences addObjectsFromArray:WMMReadPackReferenceSummariesFile(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"world_behavior_packs.json"],
                @"Behavior Pack"
            )];
            [packReferences addObjectsFromArray:WMMReadPackReferenceSummariesFile(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"world_resource_packs.json"],
                @"Resource Pack"
            )];
            [packReferences addObjectsFromArray:WMMLoadEmbeddedPackReferenceSummaries(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"behavior_packs"],
                @"Behavior Pack"
            )];
            [packReferences addObjectsFromArray:WMMLoadEmbeddedPackReferenceSummaries(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"resource_packs"],
                @"Resource Pack"
            )];
            if (packReferences.count > 0) {
                metadata[@"packReferences"] = packReferences;
            }
        } else {
            NSDictionary<NSString *, id> *header = WMMReadManifestHeader(
                &functions,
                afcConnection,
                [itemRemotePath stringByAppendingPathComponent:@"manifest.json"]
            );
            NSString *manifestName = [header[@"name"] isKindOfClass:[NSString class]] ? header[@"name"] : nil;
            metadata[@"displayName"] = manifestName.length > 0 ? manifestName : folderName;

            if ([header[@"uuid"] isKindOfClass:[NSString class]]) {
                metadata[@"packUUID"] = [header[@"uuid"] lowercaseString];
            }
            NSString *version = WMMVersionStringFromValue(header[@"version"]);
            if (version.length > 0) {
                metadata[@"packVersion"] = version;
            }
            NSString *minimumEngineVersion = WMMVersionStringFromValue(header[@"min_engine_version"]);
            if (minimumEngineVersion.length > 0) {
                metadata[@"minimumEngineVersion"] = minimumEngineVersion;
            }
        }

        [results addObject:metadata];
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"path": normalizedRootPath,
        @"items": results
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceMinecraftIconBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSArray<NSDictionary<NSString *, id> *> *items,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(20, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedRootPath = WMMNormalizedAFCPath(relativePath);
    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];

    for (NSDictionary<NSString *, id> *item in items) {
        NSString *contentType = [item[@"contentType"] isKindOfClass:[NSString class]] ? item[@"contentType"] : nil;
        NSString *relativeItemPath = [item[@"relativePath"] isKindOfClass:[NSString class]] ? item[@"relativePath"] : nil;
        if (contentType.length == 0 || relativeItemPath.length == 0) {
            continue;
        }

        NSString *itemRemotePath = [normalizedRootPath stringByAppendingPathComponent:relativeItemPath];
        for (NSString *candidateFileName in WMMIconCandidateFileNamesForContentType(contentType)) {
            NSString *candidateRemotePath = [itemRemotePath stringByAppendingPathComponent:candidateFileName];
            NSData *data = WMMCopyAFCFileData(&functions, afcConnection, candidateRemotePath, NULL);
            if (data == nil) {
                continue;
            }

            [results addObject:@{
                @"relativePath": relativeItemPath,
                @"iconFileName": candidateFileName,
                @"data": data
            }];
            break;
        }
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"path": normalizedRootPath,
        @"items": results
    };
}

NSData * _Nullable
WMMCopyConnectedDeviceAppFileData(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(17, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedPath = WMMNormalizedAFCPath(relativePath);
    NSData *data = WMMCopyAFCFileData(&functions, afcConnection, normalizedPath, error);

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return data;
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathMetrics(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(18, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *normalizedPath = WMMNormalizedAFCPath(relativePath);
    NSDictionary<NSString *, id> *metrics = WMMCopyAFCTreeMetrics(
        &functions,
        afcConnection,
        normalizedPath,
        error
    );

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    if (metrics == nil) {
        return nil;
    }

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"path": normalizedPath,
        @"sizeBytes": metrics[@"sizeBytes"] ?: @0,
        @"modifiedDate": metrics[@"modifiedDate"] ?: [NSNull null]
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceAppPathMetricsBatch(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSArray<NSString *> *relativePaths,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(21, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
    for (NSString *relativePath in relativePaths) {
        if (![relativePath isKindOfClass:[NSString class]] || relativePath.length == 0) {
            continue;
        }

        NSString *normalizedPath = WMMNormalizedAFCPath(relativePath);
        NSDictionary<NSString *, id> *metrics = WMMCopyAFCTreeMetrics(
            &functions,
            afcConnection,
            normalizedPath,
            NULL
        );

        NSMutableDictionary<NSString *, id> *result = [@{
            @"relativePath": relativePath
        } mutableCopy];
        if (metrics != nil) {
            result[@"sizeBytes"] = metrics[@"sizeBytes"] ?: @0;
            result[@"modifiedDate"] = metrics[@"modifiedDate"] ?: [NSNull null];
        }
        [results addObject:result];
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"items": results
    };
}

NSDictionary<NSString *, id> * _Nullable
WMMCopyConnectedDeviceApplicationDetails(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(12, @"A bundle identifier is required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *deviceName = WMMDeviceStringValue(&functions, device, CFSTR("DeviceName")) ?: @"Unknown Device";
    NSString *productType = WMMDeviceStringValue(&functions, device, CFSTR("ProductType")) ?: @"";
    NSString *productVersion = WMMDeviceStringValue(&functions, device, CFSTR("ProductVersion")) ?: @"";
    NSString *resolvedDeviceIdentifier = WMMResolvedDeviceIdentifier(&functions, device);

    CFDictionaryRef appDictionary = NULL;
    const int lookupStatus = functions.AMDeviceLookupApplications(device, NULL, &appDictionary);
    WMMDisconnectDevice(&functions, device, YES);
    functions.AMDeviceRelease(device);

    if (lookupStatus != 0 || appDictionary == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(lookupStatus, [NSString stringWithFormat:@"AMDeviceLookupApplications failed (%d).", lookupStatus]);
        }
        return nil;
    }

    NSDictionary *bridgedApps = CFBridgingRelease(appDictionary);
    NSDictionary *appInfo = [bridgedApps objectForKey:bundleIdentifier];
    if (![appInfo isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = WMMMakeError(13, [NSString stringWithFormat:@"No app record was found for %@.", bundleIdentifier]);
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *details = [NSMutableDictionary dictionary];
    [appInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:[NSString class]]) {
            return;
        }

        NSString *detailKey = (NSString *)key;
        if ([obj isKindOfClass:[NSString class]]) {
            details[detailKey] = (NSString *)obj;
            return;
        }
        if ([obj isKindOfClass:[NSNumber class]]) {
            details[detailKey] = [(NSNumber *)obj stringValue];
            return;
        }
        if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
            if (jsonData != nil) {
                details[detailKey] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"";
            }
        }
    }];

    return @{
        @"deviceName": deviceName,
        @"deviceIdentifier": resolvedDeviceIdentifier,
        @"productType": productType,
        @"productVersion": productVersion,
        @"bundleIdentifier": bundleIdentifier,
        @"details": details
    };
}

BOOL
WMMCopyConnectedDeviceAppSubtreeToLocalDirectory(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *relativePath,
    NSURL *destinationDirectoryURL,
    NSError **error
) {
    if (bundleIdentifier.length == 0) {
        if (error != NULL) {
            *error = WMMMakeError(14, @"A bundle identifier is required.");
        }
        return NO;
    }

    if (destinationDirectoryURL == nil || !destinationDirectoryURL.isFileURL) {
        if (error != NULL) {
            *error = WMMMakeError(15, @"A local destination directory is required.");
        }
        return NO;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return NO;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return NO;
    }

    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return NO;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return NO;
    }

    NSString *normalizedPath = relativePath.length == 0 ? @"/" : relativePath;
    if (![normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [@"/" stringByAppendingString:normalizedPath];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtURL:destinationDirectoryURL error:nil];

    BOOL success = WMMCopyAFCTreeToLocalURL(
        &functions,
        afcConnection,
        normalizedPath,
        destinationDirectoryURL,
        error
    );

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);

    if (!success) {
        [fileManager removeItemAtURL:destinationDirectoryURL error:nil];
    }

    return success;
}

NSString * _Nullable
WMMInstallLocalDirectoryInConnectedDeviceApp(
    NSString *deviceIdentifier,
    NSString *bundleIdentifier,
    NSString *minecraftRootRelativePath,
    NSString *collectionFolderName,
    NSString *preferredDestinationName,
    NSURL *sourceDirectoryURL,
    NSError **error
) {
    if (bundleIdentifier.length == 0 ||
        minecraftRootRelativePath.length == 0 ||
        collectionFolderName.length == 0 ||
        preferredDestinationName.length == 0 ||
        sourceDirectoryURL == nil ||
        !sourceDirectoryURL.isFileURL) {
        if (error != NULL) {
            *error = WMMMakeError(16, @"A device, Minecraft path, collection, destination name, and local source directory are required.");
        }
        return nil;
    }

    WMMMobileDeviceFunctions functions;
    if (!WMMLoadFunctions(&functions, error)) {
        return nil;
    }
    if (functions.AFCFileRefWrite == NULL ||
        functions.AFCDirectoryCreate == NULL ||
        functions.AFCRenamePath == NULL ||
        functions.AFCRemovePath == NULL) {
        if (error != NULL) {
            *error = WMMMakeError(17, @"This version of MobileDevice.framework does not provide the required AFC write operations.");
        }
        return nil;
    }

    AMDeviceRef device = WMMCopyConnectedDevice(&functions, deviceIdentifier, error);
    if (device == NULL) {
        return nil;
    }
    if (!WMMConnectAndValidateDevice(&functions, device, YES, error)) {
        functions.AMDeviceRelease(device);
        return nil;
    }

    AMDServiceConnectionRef backingServiceConnection = NULL;
    AFCConnectionRef afcConnection = WMMCreateVendAFCConnection(
        &functions,
        device,
        bundleIdentifier,
        &backingServiceConnection,
        error
    );
    if (afcConnection == NULL) {
        WMMCloseVendSession(&functions, device, YES, NULL, backingServiceConnection);
        functions.AMDeviceRelease(device);
        return nil;
    }

    NSString *minecraftRoot = WMMNormalizedAFCPath(minecraftRootRelativePath);
    NSString *stagingRoot = [minecraftRoot stringByAppendingPathComponent:@".world-manager-staging"];
    NSString *stagedItemPath = [stagingRoot stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *collectionPath = [minecraftRoot stringByAppendingPathComponent:collectionFolderName];

    BOOL success =
        WMMEnsureAFCDirectory(&functions, afcConnection, stagingRoot, error) &&
        WMMEnsureAFCDirectory(&functions, afcConnection, stagedItemPath, error) &&
        WMMCopyLocalTreeToAFCPath(&functions, afcConnection, sourceDirectoryURL, stagedItemPath, error) &&
        WMMEnsureAFCDirectory(&functions, afcConnection, collectionPath, error);

    NSString *destinationName = nil;
    if (success) {
        NSMutableArray<NSString *> *existingEntries = nil;
        const int listStatus = WMMReadAFCDirectory(&functions, afcConnection, collectionPath, &existingEntries);
        if (listStatus != 0) {
            if (error != NULL) {
                *error = WMMMakeError(
                    listStatus,
                    [NSString stringWithFormat:@"Could not list the destination collection %@ (%d).", collectionPath, listStatus]
                );
            }
            success = NO;
        } else {
            NSSet<NSString *> *existingNames = [NSSet setWithArray:existingEntries ?: @[]];
            destinationName = preferredDestinationName;
            NSUInteger suffix = 2;
            while ([existingNames containsObject:destinationName]) {
                destinationName = [NSString stringWithFormat:@"%@-%lu", preferredDestinationName, (unsigned long)suffix];
                suffix += 1;
            }

            NSString *destinationPath = [collectionPath stringByAppendingPathComponent:destinationName];
            const int renameStatus = functions.AFCRenamePath(
                afcConnection,
                stagedItemPath.fileSystemRepresentation,
                destinationPath.fileSystemRepresentation
            );
            if (renameStatus != 0) {
                if (error != NULL) {
                    *error = WMMMakeError(
                        renameStatus,
                        [NSString stringWithFormat:@"AFCRenamePath failed from %@ to %@ (%d).", stagedItemPath, destinationPath, renameStatus]
                    );
                }
                success = NO;
            }
        }
    }

    if (!success) {
        WMMRemoveAFCTree(&functions, afcConnection, stagedItemPath);
        destinationName = nil;
    }

    WMMCloseVendSession(&functions, device, YES, afcConnection, backingServiceConnection);
    functions.AMDeviceRelease(device);
    return destinationName;
}
