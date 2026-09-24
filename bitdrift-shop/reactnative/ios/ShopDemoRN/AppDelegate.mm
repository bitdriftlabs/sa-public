#import "AppDelegate.h"

#import <React/RCTBundleURLProvider.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"BitdriftShop";
  self.initialProps = @{};

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

// RCTAppDelegate formally conforms to UISceneDelegate but never implements
// scene:willConnectToSession:options: — it only ever builds a scene-less
// UIWindow via loadReactNativeWindow (see automaticallyLoadReactNativeWindow
// below), relying on iOS's legacy auto-attach-to-implicit-scene behavior.
// That behavior stops once Info.plist declares UIApplicationSceneManifest
// (needed to avoid a fatal EXC_BREAKPOINT on this iOS 27 simulator otherwise),
// so without this override the app no longer crashes but shows a black
// screen: iOS creates a real UIWindowScene and waits for a window to be
// attached to it, which never happens. This attaches one.
- (BOOL)automaticallyLoadReactNativeWindow
{
  return NO;
}

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions
{
  if (![scene isKindOfClass:[UIWindowScene class]]) {
    return;
  }
  UIWindowScene *windowScene = (UIWindowScene *)scene;
  // UIKit allocates a brand-new AppDelegate instance to serve as the scene
  // delegate (per UISceneDelegateClassName in Info.plist) — it does NOT reuse
  // the shared app delegate singleton `didFinishLaunchingWithOptions` ran on,
  // even though both are the same class. `self` here has none of that
  // instance's state (rootViewFactory, moduleName, initialProps are all nil),
  // so everything below must go through the real shared instance instead.
  AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
  UIView *rootView = [appDelegate.rootViewFactory viewWithModuleName:appDelegate.moduleName
                                                    initialProperties:appDelegate.initialProps
                                                         launchOptions:nil];
  appDelegate.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  UIViewController *rootViewController = [appDelegate createRootViewController];
  [appDelegate setRootView:rootView toRootViewController:rootViewController];
  appDelegate.window.rootViewController = rootViewController;
  [appDelegate.window makeKeyAndVisible];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end
