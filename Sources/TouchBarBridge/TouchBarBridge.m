#import "TouchBarBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

static void *dfrFramework(void) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ framework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY); });
    return framework;
}
static void setPresence(NSString *identifier, BOOL visible) {
    void *framework = dfrFramework();
    if (!framework) return;
    void (*presence)(NSString *, BOOL) = dlsym(framework, "DFRElementSetControlStripPresenceForIdentifier");
    if (presence) presence(identifier, visible);
}

// Global Touch Bar presentation has no public API. Resolve optional selectors
// at runtime so unsupported macOS versions still get the desktop dashboard.
static SEL presentationSelector(void) {
    return NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
}
BOOL HTBAvailable(void) { return [NSTouchBar respondsToSelector:presentationSelector()]; }
BOOL HTBInstallLauncher(NSCustomTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"addSystemTrayItem:");
    if (![NSTouchBarItem respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(NSTouchBarItem.class, selector, item);
    setPresence(item.identifier, YES);
    return YES;
}
BOOL HTBPresent(NSTouchBar *bar, NSString *identifier) {
    if (!HTBAvailable()) return NO;
    // Retain the system close affordance; users can always dismiss the bar.
    void *framework = dfrFramework();
    if (framework) {
        void (*showClose)(BOOL) = dlsym(framework, "DFRSystemModalShowsCloseBoxWhenFrontMost");
        if (showClose) showClose(YES);
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(NSTouchBar.class, presentationSelector(), bar, identifier);
    return YES;
}
void HTBDismiss(NSTouchBar *bar) {
    SEL selector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if ([NSTouchBar respondsToSelector:selector]) ((void (*)(id, SEL, id))objc_msgSend)(NSTouchBar.class, selector, bar);
}
void HTBRemoveLauncher(NSCustomTouchBarItem *item) {
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    setPresence(item.identifier, NO);
    if ([NSTouchBarItem respondsToSelector:selector]) ((void (*)(id, SEL, id))objc_msgSend)(NSTouchBarItem.class, selector, item);
}
