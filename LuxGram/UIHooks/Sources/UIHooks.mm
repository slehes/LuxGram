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
 *  7. Disable media copy protection (TelegramMediaFile.isVoice → treat audio as voice)
 *
 * MARK: - LuxGram
 */

#import "Headers.h"

// MARK: - 1. Copy/Forward Protection Bypass

ORIG_IMP(BOOL, copyProtectionEnabled);
ORIG_IMP(BOOL, noForwards);
ORIG_IMP(id,   adAttribute);

static BOOL _uh_copyProtectionEnabled(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableForwardRestriction]) {
        return NO;
    }
    return CALL_ORIG(BOOL, self, copyProtectionEnabled);
}

static BOOL _uh_noForwards(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableForwardRestriction]) {
        return NO;
    }
    return CALL_ORIG(BOOL, self, noForwards);
}

static id _uh_adAttribute(id self, SEL _cmd) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kLGDisableAllAds]) {
        return nil;
    }
    return CALL_ORIG(id, self, adAttribute);
}

static void _uh_installCopyProtectionHooks(void) {
    // Hook copyProtectionEnabled on both possible class name manglings
    Class cls1 = objc_getClass("_TtC10TelegramUI29ChatPresentationInterfaceState");
    Class cls2 = objc_getClass("_TtC30ChatPresentationInterfaceState30ChatPresentationInterfaceState");
    SEL sel = @selector(copyProtectionEnabled);

    if (cls1) {
        UHSwizzleInstanceMethod(cls1, sel, (IMP)_uh_copyProtectionEnabled, &_orig_copyProtectionEnabled);
        UHLog(@"Hooked copyProtectionEnabled on TelegramUI.ChatPresentationInterfaceState");
    }
    if (cls2 && cls2 != cls1) {
        // Use the same IMP — both call through the same _orig pointer
        UHSwizzleInstanceMethod(cls2, sel, (IMP)_uh_copyProtectionEnabled, &_orig_copyProtectionEnabled);
        UHLog(@"Hooked copyProtectionEnabled on ChatPresentationInterfaceState.ChatPresentationInterfaceState");
    }

    // Hook noForwards on ChatMessageItem
    Class chatMsgItemCls = objc_getClass("_TtC10TelegramUI15ChatMessageItem");
    if (chatMsgItemCls) {
        UHSwizzleInstanceMethod(chatMsgItemCls, @selector(noForwards), (IMP)_uh_noForwards, &_orig_noForwards);
        UHLog(@"Hooked noForwards on ChatMessageItem");
    }

    // Hook noForwards on ApiChat
    Class apiChatCls = objc_getClass("_TtC10TelegramUI11ApiChat");
    if (apiChatCls) {
        UHSwizzleInstanceMethod(apiChatCls, @selector(noForwards), (IMP)_uh_noForwards, &_orig_noForwards);
        UHLog(@"Hooked noForwards on ApiChat");
    }

    // Hook adAttribute on Postbox.Message — nil out sponsored messages
    Class postboxMsgCls = objc_getClass("_TtC7Postbox7Message");
    if (postboxMsgCls) {
        UHSwizzleInstanceMethod(postboxMsgCls, @selector(adAttribute), (IMP)_uh_adAttribute, &_orig_adAttribute);
        UHLog(@"Hooked adAttribute on Postbox.Message");
    }
}

// MARK: - 2. ASDisplayNode Layout Hook (Ads, Stories)

ORIG_IMP(void, asdn_layout);

// Associated object key for leadLongPressGesture (unused but reserved)
static const char kUHAssociatedGestureKey;

static void _uh_asdn_layout(id self, SEL _cmd) {
    CALL_ORIG(void, self, asdn_layout);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *className = NSStringFromClass([self class]);

    // --- Disable All Ads: hide sponsored message nodes ---
    if ([defaults boolForKey:kLGDisableAllAds]) {
        @try {
            if ([className containsString:@"ChatSponsoredMessage"] ||
                [className containsString:@"ChatChannelAdItemNode"]) {
                UIView *view = nil;
                if ([self respondsToSelector:@selector(view)]) {
                    view = [self valueForKey:@"view"];
                }
                if (view) {
                    view.hidden = YES;
                    view.alpha = 0.0;
                }
                return;
            }

            // Also check for adAttribute on the item's message
            if ([self respondsToSelector:NSSelectorFromString(@"item")]) {
                @try {
                    id item = [self valueForKey:@"item"];
                    if (item && [item respondsToSelector:NSSelectorFromString(@"message")]) {
                        id message = [item valueForKey:@"message"];
                        if (message && [message respondsToSelector:NSSelectorFromString(@"adAttribute")]) {
                            if ([message valueForKey:@"adAttribute"] != nil) {
                                UIView *view = [self valueForKey:@"view"];
                                if (view) {
                                    view.hidden = YES;
                                    view.alpha = 0.0;
                                }
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
            if (view) {
                view.hidden = YES;
                view.alpha = 0.0;
            }
        }
    }
}

static void _uh_installASDisplayNodeHooks(void) {
    Class asdnCls = NSClassFromString(@"ASDisplayNode");
    if (asdnCls) {
        UHSwizzleInstanceMethod(asdnCls, @selector(layout), (IMP)_uh_asdn_layout, &_orig_asdn_layout);
        UHLog(@"Hooked ASDisplayNode.layout (ads + stories)");
    }
}

// MARK: - 3. Auto-Download Stories

ORIG_IMP(void, storyView_didMoveToWindow);

static void _uh_storyView_didMoveToWindow(id self, SEL _cmd) {
    CALL_ORIG(void, self, storyView_didMoveToWindow);

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

static void _uh_installStoryDownloadHook(void) {
    Class storyViewCls = objc_getClass("_TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View");
    if (storyViewCls) {
        UHSwizzleInstanceMethod(storyViewCls, @selector(didMoveToWindow), (IMP)_uh_storyView_didMoveToWindow, &_orig_storyView_didMoveToWindow);
        UHLog(@"Hooked StoryItemSetContainerComponent.View.didMoveToWindow");
    }
}

// MARK: - 4. Call Confirmation

ORIG_IMP(void, ascn_sendActions);

static void _uh_ascn_sendActions(id self, SEL _cmd, NSUInteger controlEvents, UIEvent *event) {
    if (controlEvents == (1 << 4)) { // ASControlNodeEventTouchUpInside
        NSString *label = nil;
        @try { label = [(id)self accessibilityLabel]; } @catch (NSException *e) {}

        if (label && label.length > 0 && [[NSUserDefaults standardUserDefaults] boolForKey:kLGConfirmCalls]) {
            NSString *lower = [label lowercaseString];

            NSSet *callLabels = [NSSet setWithArray:@[
                @"call", @"позвонить", @"звонок"
            ]];
            NSSet *videoLabels = [NSSet setWithArray:@[
                @"video", @"видео", @"video call", @"видеозвонок"
            ]];

            BOOL isCall = [callLabels containsObject:lower];
            BOOL isVideo = [videoLabels containsObject:lower];

            if (isCall || isVideo) {
                UIWindow *window = nil;
                @try { window = [UIApplication sharedApplication].keyWindow; } @catch (NSException *e) {}
                UIViewController *rootVC = window.rootViewController;
                while (rootVC.presentedViewController) {
                    rootVC = rootVC.presentedViewController;
                }
                if (rootVC) {
                    NSString *confirmTitle = isVideo ? @"Video Call" : @"Call";
                    NSString *alertTitle = isVideo ? @"Start Video Call?" : @"Start Call?";

                    UIAlertController *alert = [UIAlertController
                        alertControllerWithTitle:alertTitle
                        message:nil
                        preferredStyle:UIAlertControllerStyleAlert];

                    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                             style:UIAlertActionStyleCancel
                                                           handler:nil]];
                    [alert addAction:[UIAlertAction actionWithTitle:confirmTitle
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *action) {
                        CALL_ORIG(void, self, ascn_sendActions, controlEvents, event);
                    }]];

                    [rootVC presentViewController:alert animated:YES completion:nil];
                    return;
                }
            }
        }
    }
    CALL_ORIG(void, self, ascn_sendActions, controlEvents, event);
}

static void _uh_installCallConfirmHook(void) {
    Class cls = NSClassFromString(@"ASControlNode");
    if (cls) {
        UHSwizzleInstanceMethod(cls, @selector(sendActionsForControlEvents:withEvent:),
                                (IMP)_uh_ascn_sendActions, &_orig_ascn_sendActions);
        UHLog(@"Hooked ASControlNode.sendActionsForControlEvents (call confirm)");
    }
}

// MARK: - 5. Siri Authorization Bypass

static IMP _orig_inpref_initialize = NULL;
static IMP _orig_inpref_sharedPreferences = NULL;
static IMP _orig_inpref_alloc = NULL;
static IMP _orig_inpref_new = NULL;
static IMP _orig_inpref_init = NULL;
static IMP _orig_inpref_siriAuthorizationStatus = NULL;
static IMP _orig_inpref_requestSiriAuthorization = NULL;

static void _uh_inpref_initialize(id self, SEL _cmd) {
    // No-op: prevent INPreferences from initializing
}

static id _uh_inpref_sharedPreferences(id self, SEL _cmd) {
    return nil;
}

static id _uh_inpref_alloc(id self, SEL _cmd) {
    return nil;
}

static id _uh_inpref_new(id self, SEL _cmd) {
    return nil;
}

static id _uh_inpref_init(id self, SEL _cmd) {
    return nil;
}

static NSInteger _uh_inpref_siriAuthorizationStatus(id self, SEL _cmd) {
    return 0; // INSiriAuthorizationStatusNotDetermined
}

static void _uh_inpref_requestSiriAuthorization(id self, SEL _cmd, void (^routine)(NSInteger)) {
    if (routine) {
        routine(0);
    }
}

static void _uh_installSiriBypassHook(void) {
    @try {
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/Intents.framework"] load];
    } @catch (NSException *e) {}

    Class cls = objc_getClass("INPreferences");
    if (!cls) {
        UHLog(@"INPreferences class not found — Siri bypass skipped");
        return;
    }

    UHSwizzleClassMethod(cls, @selector(initialize),
                         (IMP)_uh_inpref_initialize, &_orig_inpref_initialize);
    UHSwizzleClassMethod(cls, @selector(sharedPreferences),
                         (IMP)_uh_inpref_sharedPreferences, &_orig_inpref_sharedPreferences);
    UHSwizzleClassMethod(cls, @selector(alloc),
                         (IMP)_uh_inpref_alloc, &_orig_inpref_alloc);
    UHSwizzleClassMethod(cls, @selector(new),
                         (IMP)_uh_inpref_new, &_orig_inpref_new);
    UHSwizzleInstanceMethod(cls, @selector(init),
                            (IMP)_uh_inpref_init, &_orig_inpref_init);
    UHSwizzleClassMethod(cls, @selector(siriAuthorizationStatus),
                         (IMP)_uh_inpref_siriAuthorizationStatus, &_orig_inpref_siriAuthorizationStatus);
    UHSwizzleClassMethod(cls, @selector(requestSiriAuthorization:),
                         (IMP)_uh_inpref_requestSiriAuthorization, &_orig_inpref_requestSiriAuthorization);

    UHLog(@"Hooked INPreferences (Siri bypass)");
}

// MARK: - 6. TelegramMediaFile — Send Audio as Voice

ORIG_IMP(BOOL, tmf_isVoice);

@interface _TtC12TelegramCore16TelegramMediaFile : NSObject
- (NSString *)mimeType;
@end

static BOOL _uh_tmf_isVoice(id self, SEL _cmd) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kLGSendAsVoice]) {
        return CALL_ORIG(BOOL, self, tmf_isVoice);
    }
    if (CALL_ORIG(BOOL, self, tmf_isVoice)) return YES;
    NSString *mime = [(id)self mimeType];
    if ([mime hasPrefix:@"audio/"]) {
        return YES;
    }
    return NO;
}

static void _uh_installMediaFileHook(void) {
    Class cls = objc_getClass("_TtC12TelegramCore16TelegramMediaFile");
    if (cls) {
        UHSwizzleInstanceMethod(cls, @selector(isVoice), (IMP)_uh_tmf_isVoice, &_orig_tmf_isVoice);
        UHLog(@"Hooked TelegramMediaFile.isVoice");
    }
}

// MARK: - Public Initialization (called from Swift)

__attribute__((visibility("default")))
void LuxGramInstallUIHooks(void) {
    UHLog(@"Installing UIHooks...");

    // Siri bypass — immediate, doesn't need main queue
    _uh_installSiriBypassHook();

    // Copy/forward protection + ad attribute
    _uh_installCopyProtectionHooks();

    // ASDisplayNode layout (ads + stories)
    _uh_installASDisplayNodeHooks();

    // Story auto-download
    _uh_installStoryDownloadHook();

    // Call confirmation
    _uh_installCallConfirmHook();

    // Media file voice override
    _uh_installMediaFileHook();

    // Register extra defaults not in SGSimpleSettings
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kLGDisableForwardRestriction: @NO,
        kLGSendAsVoice: @NO,
    }];

    UHLog(@"All UIHooks installed successfully");
}

// MARK: - End LuxGram