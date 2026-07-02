#ifndef UIHooks_Headers_h
#define UIHooks_Headers_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - LuxGram UIHooks Settings Keys
// Keys match SGSimpleSettings.Keys.rawValue where they exist.
// Extra keys (disableForwardRestriction, sendAsVoice) are LuxGram-UIHooks-only.

static NSString *const kLGDisableAllAds              = @"disableAllAds";
static NSString *const kLGHideStories                = @"hideStories";
static NSString *const kLGDownloadStories            = @"downloadStories";
static NSString *const kLGConfirmCalls               = @"confirmCalls";
static NSString *const kLGDisableForwardRestriction  = @"disableForwardRestriction";
static NSString *const kLGSendAsVoice                = @"sendAsVoice";

// MARK: - Logging

#ifndef UIHOOKS_LOG_LEVEL
#define UIHOOKS_LOG_LEVEL 1
#endif

#if UIHOOKS_LOG_LEVEL
#define UHLog(fmt, ...) NSLog(@"[UIHooks] " fmt, ##__VA_ARGS__)
#else
#define UHLog(fmt, ...)
#endif

// MARK: - Runtime Swizzling Helpers

static inline void UHSwizzleInstanceMethod(Class cls, SEL originalSel, IMP newImp, IMP *outOriginalImp) {
    Method method = class_getInstanceMethod(cls, originalSel);
    if (!method) {
        UHLog(@"WARN: method %@ not found on %@", NSStringFromSelector(originalSel), cls);
        return;
    }
    *outOriginalImp = method_getImplementation(method);
    method_setImplementation(method, newImp);
}

static inline void UHSwizzleClassMethod(Class cls, SEL originalSel, IMP newImp, IMP *outOriginalImp) {
    Method method = class_getClassMethod(cls, originalSel);
    if (!method) {
        UHLog(@"WARN: class method %@ not found on %@", NSStringFromSelector(originalSel), cls);
        return;
    }
    *outOriginalImp = method_getImplementation(method);
    method_setImplementation(method, newImp);
}

#define ORIG_IMP(type, sel) static type _orig_##sel = NULL
#define CALL_ORIG(type, obj, sel, ...) ((type (*)(id, SEL, ...))_orig_##sel)((id)(obj), sel, ##__VA_ARGS__)

#endif /* UIHooks_Headers_h */