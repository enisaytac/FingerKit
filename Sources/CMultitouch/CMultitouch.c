#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef, TMTouch *, int, double, int);

// Fonksiyonlar derleme sırasında değil, açılışta parçadan aranır (dlopen/dlsym);
// böylece SDK'da başlık dosyası olmasa da derlenir.
static CFArrayRef (*p_MTDeviceCreateList)(void);
static void (*p_MTRegisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*p_MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*p_MTDeviceStart)(MTDeviceRef, int);
static void (*p_MTDeviceStop)(MTDeviceRef);
static int (*p_MTDeviceGetSensorSurfaceDimensions)(MTDeviceRef, int *, int *);
static bool (*p_MTDeviceIsBuiltIn)(MTDeviceRef);

static CFArrayRef devices;
static CFMutableSetRef running;
static TMFrameCallback userCallback;

static int contactCallback(MTDeviceRef device, TMTouch *touches, int count, double timestamp, int frame) {
    (void)frame;
    TMFrameCallback callback = userCallback;
    if (callback) callback(device, touches, count, timestamp);
    return 0;
}

bool tm_load(void) {
    static void *handle;
    if (handle) return true;
    handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!handle) return false;
    p_MTDeviceCreateList = dlsym(handle, "MTDeviceCreateList");
    p_MTRegisterContactFrameCallback = dlsym(handle, "MTRegisterContactFrameCallback");
    p_MTUnregisterContactFrameCallback = dlsym(handle, "MTUnregisterContactFrameCallback");
    p_MTDeviceStart = dlsym(handle, "MTDeviceStart");
    p_MTDeviceStop = dlsym(handle, "MTDeviceStop");
    p_MTDeviceGetSensorSurfaceDimensions = dlsym(handle, "MTDeviceGetSensorSurfaceDimensions");
    p_MTDeviceIsBuiltIn = dlsym(handle, "MTDeviceIsBuiltIn");
    return p_MTDeviceCreateList && p_MTRegisterContactFrameCallback && p_MTDeviceStart && p_MTDeviceStop;
}

int tm_refresh_devices(void) {
    tm_stop_all();
    if (devices) CFRelease(devices);
    devices = p_MTDeviceCreateList ? p_MTDeviceCreateList() : NULL;
    return devices ? (int)CFArrayGetCount(devices) : 0;
}

void *tm_device_at(int index) {
    if (!devices || index < 0 || index >= CFArrayGetCount(devices)) return NULL;
    return (void *)CFArrayGetValueAtIndex(devices, index);
}

bool tm_device_size(void *device, int *width, int *height) {
    if (!p_MTDeviceGetSensorSurfaceDimensions) return false;
    return p_MTDeviceGetSensorSurfaceDimensions(device, width, height) == 0;
}

bool tm_device_is_builtin(void *device) {
    return p_MTDeviceIsBuiltIn ? p_MTDeviceIsBuiltIn(device) : false;
}

void tm_set_callback(TMFrameCallback callback) {
    userCallback = callback;
}

void tm_device_start(void *device) {
    if (!running) running = CFSetCreateMutable(NULL, 0, NULL);
    if (CFSetContainsValue(running, device)) return;
    p_MTRegisterContactFrameCallback(device, contactCallback);
    p_MTDeviceStart(device, 0);
    CFSetAddValue(running, device);
}

static void stopDevice(const void *device, void *context) {
    (void)context;
    if (p_MTUnregisterContactFrameCallback) p_MTUnregisterContactFrameCallback((MTDeviceRef)device, contactCallback);
    p_MTDeviceStop((MTDeviceRef)device);
}

void tm_stop_all(void) {
    if (!running) return;
    CFSetApplyFunction(running, stopDevice, NULL);
    CFSetRemoveAllValues(running);
}
