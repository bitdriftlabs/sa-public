// Native crash module for the React Native demo — the iOS counterpart to the Android
// app's native-signal crashes. Exposed to JS as NativeModules.BdCrash (src/sim/crashes.ts).
//
// Each native signal method calls kill() directly so each crash has a distinct top
// frame for bitdrift's issue grouper.

#import <React/RCTBridgeModule.h>
#import <signal.h>
#import <unistd.h>
#import <stdlib.h>

@interface BdCrash : NSObject <RCTBridgeModule>
@end

@implementation BdCrash

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(nativeSigsegv) {
  kill(getpid(), SIGSEGV);
}

RCT_EXPORT_METHOD(nativeSigbus) {
  kill(getpid(), SIGBUS);
}

RCT_EXPORT_METHOD(nativeSigabrt) {
  kill(getpid(), SIGABRT);
}

RCT_EXPORT_METHOD(nativeSigfpe) {
  kill(getpid(), SIGFPE);
}

RCT_EXPORT_METHOD(unsatisfiedLink) {
  // iOS analogue of a missing native symbol: abort with a recognisable signal.
  abort();
}

// True ANR: block the main thread so the watchdog/responsiveness signal fires.
RCT_EXPORT_METHOD(blockMainThread:(double)ms) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSThread sleepForTimeInterval:ms / 1000.0];
    while (true) {
      [NSThread sleepForTimeInterval:60.0];
    }
  });
}

RCT_EXPORT_METHOD(forceQuit) {
  exit(0);
}

@end
