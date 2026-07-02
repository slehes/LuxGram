/**
 * UIHooks.mm — LuxGram Objective-C Runtime Hooks
 *
 * Converted from Logos (%hook) syntax to plain objc_runtime swizzling.
 * Provides low-level UI intercepts that complement the Swift-based
 * implementations in SGSimpleSettings / TelegramUI patches.
 *
 * Features:
 *  1. Disable copy/forward protection (noForwards, copyProtectionEnabled)
 *  2. Remove ads at UI node level (ChatSponsoredMessage, adAttribute)
 *  3. Hide stories (StoryPeerList, StoryContainer, etc.)
 *  4. Auto-download stories when opened
 *  5. Call confirmation dialog before placing calls
 *  6. Siri authorization bypass
 *  7. Disable media copy protection (TelegramMediaFile.isVoice -> treat audio as voice)
 *
 * MARK: - LuxGram
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Settings Keys (match SGSimpleSettings.Keys.rawValue where applicable)

static NSString *const kLGDisableAllAds              = @"disableAllAds";
static NSString *const kLGHideStories                = @"hideStories";
static NSString *const kLGDownloadStories            = @"downloadStories";
static NSString *const kLGConfirmCalls               = @"confirmCalls";
static NSString *const kLGDisableForwardRestriction  = @"disableForwardRestriction";
static NSString *const kLGSendAsVoice                = @"sendAsVoice";

// MARK: - Logging

#define UHLog(fmt, ...) NSLog(@"[UIHooks] " fmt, ##__VA_ARGS__)

// MARK: - Swizzle Helper

static void UHSwizzle(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *outOrig = method_setImplementation(m, newImp);
}

// MARK: - 1. Copy/Forward Protection Bypass

static IMP _orig_copyProtectionEnabled = NULL;
static IMP _orig_noForwards = NULL;
static IMP _orig_adAttribute = NULL;

static BOOL _replaced_copyProtectionEnabled(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableForwardRestriction]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))_orig_copyProtectionEnabled)(self, _cmd);
}

static BOOL _replaced_noForwards(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableForwardRestriction]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))_orig_noForwards)(self, _cmd);
}

static id _replaced_adAttribute(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableAllAds]) {
        return nil;
    }
    return ((id (*)(id, SEL))_orig_adAttribute)(self, _cmd);
}

static void installCopyProtectionHooks(void) {
    Class cls1 = objc_getClass("_TtC10TelegramUI29ChatPresentationInterfaceState");
    Class cls2 = objc_getClass("_TtC30ChatPresentationInterfaceState30ChatPresentationInterfaceState");
    SEL sel = @selector(copyProtectionEnabled);

    if (cls1) {
        UHSwizzle(cls1, sel, (IMP)_replaced_copyProtectionEnabled, &_orig_copyProtectionEnabled);
        UHLog(@"Hooked copyProtectionEnabled on TelegramUI.ChatPresentationInterfaceState");
    }
    if (cls2 && cls2 != cls1) {
        UHSwizzle(cls2, sel, (IMP)_replaced_copyProtectionEnabled, &_orig_copyProtectionEnabled);
        UHLog(@"Hooked copyProtectionEnabled on ChatPresentationInterfaceState.ChatPresentationInterfaceState");
    }

    Class chatMsgItemCls = objc_getClass("_TtC10TelegramUI15ChatMessageItem");
    if (chatMsgItemCls) {
        UHSwizzle(chatMsgItemCls, @selector(noForwards), (IMP)_replaced_noForwards, &_orig_noForwards);
        UHLog(@"Hooked noForwards on ChatMessageItem");
    }

    Class apiChatCls = objc_getClass("_TtC10TelegramUI11ApiChat");
    if (apiChatCls) {
        UHSwizzle(apiChatCls, @selector(noForwards), (IMP)_replaced_noForwards, &_orig_noForwards);
        UHLog(@"Hooked noForwards on ApiChat");
    }

    Class postboxMsgCls = objc_getClass("_TtC7Postbox7Message");
    if (postboxMsgCls) {
        UHSwizzle(postboxMsgCls, @selector(adAttribute), (IMP)_replaced_adAttribute, &_orig_adAttribute);
        UHLog(@"Hooked adAttribute on Postbox.Message");
    }
}

// MARK: - 2. ASDisplayNode Layout Hook (Ads + Stories)

static IMP _orig_layout = NULL;

static void _replaced_layout(id self, SEL _cmd) {
    ((void (*)(id, SEL))_orig_layout)(self, _cmd);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *className = NSStringFromClass([self class]);

    // --- Disable All Ads ---
    if ([defaults boolForKey:kLGDisableAllAds]) {
        @try {
            if ([className containsString:@"ChatSponsoredMessage"] ||
                [className containsString:@"ChatChannelAdItemNode"]) {
                UIView *view = nil;
                if ([self respondsToSelector:@selector(view)]) {
                    @try { view = [self valueForKey:@"view"]; } @catch (NSException *e) {}
                }
                if (view) { view.hidden = YES; view.alpha = 0.0; }
                return;
            }

            if ([self respondsToSelector:NSSelectorFromString(@"item")]) {
                @try {
                    id item = [self valueForKey:@"item"];
                    if (item && [item respondsToSelector:NSSelectorFromString(@"message")]) {
                        id message = [item valueForKey:@"message"];
                        if (message && [message respondsToSelector:NSSelectorFromString(@"adAttribute")]) {
                            if ([message valueForKey:@"adAttribute"] != nil) {
                                UIView *view = nil;
                                @try { view = [self valueForKey:@"view"]; } @catch (NSException *e) {}
                                if (view) { view.hidden = YES; view.alpha = 0.0; }
                                return;
                            }
                        }
                    }
                } @catch (NSException *e) {}
            }
        } @catch (NSException *e) {}
    }

    // --- Hide Stories ---
    if ([defaults boolForKey:kLGHideStories]) {
        if ([className containsString:@"StoryPeerList"] ||
            [className containsString:@"StoryContainer"] ||
            [className containsString:@"StorySetIndicator"] ||
            [className containsString:@"AvatarStoryIndicator"]) {
            UIView *view = nil;
            if ([self respondsToSelector:@selector(view)]) {
                @try { view = [self valueForKey:@"view"]; } @catch (NSException *e) {}
            }
            if (view) { view.hidden = YES; view.alpha = 0.0; }
        }
    }
}

static void installASDisplayNodeHooks(void) {
    Class cls = NSClassFromString(@"ASDisplayNode");
    if (cls) {
        UHSwizzle(cls, @selector(layout), (IMP)_replaced_layout, &_orig_layout);
        UHLog(@"Hooked ASDisplayNode.layout (ads + stories)");
    }
}

// MARK: - 3. Auto-Download Stories

static IMP _orig_didMoveToWindow = NULL;

static void _replaced_didMoveToWindow(id self, SEL _cmd) {
    ((void (*)(id, SEL))_orig_didMoveToWindow)(self, _cmd);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:kLGDownloadStories]) return;
    if (![(UIView *)self window]) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDownloadStories]) {
                if ([self respondsToSelector:@selector(requestSave)]) {
                    ((void (*)(id, SEL))[self methodForSelector:@selector(requestSave)])(self, @selector(requestSave));
                    UHLog(@"Auto-saved story");
                }
            }
        } @catch (NSException *e) {}
    });
}

static void installStoryDownloadHook(void) {
    Class cls = objc_getClass("_TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View");
    if (cls) {
        UHSwizzle(cls, @selector(didMoveToWindow), (IMP)_replaced_didMoveToWindow, &_orig_didMoveToWindow);
        UHLog(@"Hooked StoryItemSetContainerComponent.View.didMoveToWindow");
    }
}

// MARK: - 4. Call Confirmation

static IMP _orig_sendActions = NULL;

static void _replaced_sendActions(id self, SEL _cmd, NSUInteger controlEvents, UIEvent *event) {
    if (controlEvents == (1 << 4)) { // ASControlNodeEventTouchUpInside
        NSString *label = nil;
        @try { label = [(id)self accessibilityLabel]; } @catch (NSException *e) {}

        if (label && label.length > 0 && [[NSUserDefaults standardUserDefaults] boolForKey:kLGConfirmCalls]) {
            NSString *lower = [label lowercaseString];

            NSSet *callLabels = [NSSet setWithArray:@[@"call", @"позвонить", @"звонок"]];
            NSSet *videoLabels = [NSSet setWithArray:@[@"video", @"видео", @"video call", @"видеозвонок"]];

            BOOL isCall = [callLabels containsObject:lower];
            BOOL isVideo = [videoLabels containsObject:lower];

            if (isCall || isVideo) {
                UIWindow *window = nil;
                @try { window = [UIApplication sharedApplication].keyWindow; } @catch (NSException *e) {}
                UIViewController *rootVC = window.rootViewController;
                while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }

                if (rootVC) {
                    NSString *confirmTitle = isVideo ? @"Video Call" : @"Call";
                    NSString *alertTitle = isVideo ? @"Start Video Call?" : @"Start Call?";
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:alertTitle message:nil preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:confirmTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        ((void (*)(id, SEL, NSUInteger, UIEvent *))_orig_sendActions)(self, _cmd, controlEvents, event);
                    }]];
                    [rootVC presentViewController:alert animated:YES completion:nil];
                    return;
                }
            }
        }
    }
    ((void (*)(id, SEL, NSUInteger, UIEvent *))_orig_sendActions)(self, _cmd, controlEvents, event);
}

static void installCallConfirmHook(void) {
    Class cls = NSClassFromString(@"ASControlNode");
    if (cls) {
        UHSwizzle(cls, @selector(sendActionsForControlEvents:withEvent:), (IMP)_replaced_sendActions, &_orig_sendActions);
        UHLog(@"Hooked ASControlNode.sendActionsForControlEvents (call confirm)");
    }
}

// MARK: - 5. Siri Authorization Bypass

static void installSiriBypassHook(void) {
    @try {
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/Intents.framework"] load];
    } @catch (NSException *e) {}

    Class cls = objc_getClass("INPreferences");
    if (!cls) { UHLog(@"INPreferences not found, Siri bypass skipped"); return; }

    // Block +initialize to prevent class setup
    Method m = class_getClassMethod(cls, @selector(initialize));
    if (m) { method_setImplementation(m, (IMP)(void (^)(id, SEL))^(id self, SEL _cmd) {}); }

    // Block alloc, new, sharedPreferences
    for (SEL sel in @[@selector(alloc), @selector(new), @selector(sharedPreferences)]) {
        Method cm = class_getClassMethod(cls, sel);
        if (cm) { method_setImplementation(cm, (IMP)(id (^)(id, SEL))^(id self, SEL _cmd) { return nil; }); }
    }

    // Block instance init
    Method im = class_getInstanceMethod(cls, @selector(init));
    if (im) { method_setImplementation(im, (IMP)(id (^)(id, SEL))^(id self, SEL _cmd) { return nil; }); }

    // siriAuthorizationStatus -> 0 (not determined)
    Method sa = class_getClassMethod(cls, @selector(siriAuthorizationStatus));
    if (sa) { method_setImplementation(sa, (IMP)(NSInteger (^)(id, SEL))^(id self, SEL _cmd) { return 0; }); }

    // requestSiriAuthorization: -> callback(0)
    Method ra = class_getClassMethod(cls, @selector(requestSiriAuthorization:));
    if (ra) {
        method_setImplementation(ra, (IMP)(void (^)(id, SEL, void (^)(NSInteger)))^(id self, SEL _cmd, void (^routine)(NSInteger)) {
            if (routine) routine(0);
        });
    }

    UHLog(@"Hooked INPreferences (Siri bypass)");
}

// MARK: - 6. TelegramMediaFile — Send Audio as Voice

static IMP _orig_isVoice = NULL;

static BOOL _replaced_isVoice(id self, SEL _cmd) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kLGSendAsVoice]) {
        return ((BOOL (*)(id, SEL))_orig_isVoice)(self, _cmd);
    }
    if (((BOOL (*)(id, SEL))_orig_isVoice)(self, _cmd)) return YES;
    @try {
        NSString *mime = [(id)self mimeType];
        if ([mime hasPrefix:@"audio/"]) return YES;
    } @catch (NSException *e) {}
    return NO;
}

static void installMediaFileHook(void) {
    Class cls = objc_getClass("_TtC12TelegramCore16TelegramMediaFile");
    if (cls) {
        UHSwizzle(cls, @selector(isVoice), (IMP)_replaced_isVoice, &_orig_isVoice);
        UHLog(@"Hooked TelegramMediaFile.isVoice");
    }
}

// MARK: - Public Entry Point

__attribute__((visibility("default")))
void LuxGramInstallUIHooks(void) {
    UHLog(@"Installing UIHooks...");

    installSiriBypassHook();
    installCopyProtectionHooks();
    installASDisplayNodeHooks();
    installStoryDownloadHook();
    installCallConfirmHook();
    installMediaFileHook();

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kLGDisableForwardRestriction: @NO,
        kLGSendAsVoice: @NO,
    }];

    UHLog(@"All UIHooks installed");
}

// MARK: - End LuxGram