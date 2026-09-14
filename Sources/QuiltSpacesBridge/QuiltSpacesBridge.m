#import "QuiltSpacesBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

static Class operationClass(void) {
    static void *library;
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    return library ? NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation") : Nil;
}
bool QuiltCanMoveToSpace(void) {
    Class cls = operationClass();
    return cls && [cls instancesRespondToSelector:NSSelectorFromString(@"initWithWindows:spaceID:")]
        && [cls instancesRespondToSelector:NSSelectorFromString(@"performWithWMBridgeDelegate")];
}
bool QuiltMoveToSpace(CFArrayRef windows, uint64_t space) {
    if (!QuiltCanMoveToSpace()) return false;
    @try {
        id instance = [operationClass() alloc];
        SEL initializer = NSSelectorFromString(@"initWithWindows:spaceID:");
        id (*initialize)(id, SEL, NSArray *, uint64_t) = (void *)[instance methodForSelector:initializer];
        id operation = initialize(instance, initializer, (__bridge NSArray *)windows, space);
        if (!operation) return false;
        SEL perform = NSSelectorFromString(@"performWithWMBridgeDelegate");
        void (*run)(id, SEL) = (void *)[operation methodForSelector:perform];
        run(operation, perform);
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}
