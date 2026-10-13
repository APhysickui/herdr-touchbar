#import <AppKit/AppKit.h>
BOOL HTBAvailable(void);
BOOL HTBInstallLauncher(NSCustomTouchBarItem *item);
BOOL HTBPresent(NSTouchBar *bar, NSString *identifier);
void HTBDismiss(NSTouchBar *bar);
void HTBRemoveLauncher(NSCustomTouchBarItem *item);
