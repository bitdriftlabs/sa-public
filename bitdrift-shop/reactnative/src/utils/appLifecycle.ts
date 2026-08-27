import {AppState, type AppStateStatus} from 'react-native';
import {ScreenLogger} from './logger';

// Foreground/background lifecycle events, mirroring the Android app's
// AppLifecycleCallbacks (app_open / app_close). React Native's AppState is the
// cross-platform equivalent of Android's activity start/stop callbacks.
//
// Note on memory events: the Android and iOS apps both emit `memory_pressure` (Android
// additionally emits `low_memory`) from ComponentCallbacks2.onTrimMemory / onLowMemory and
// UIApplicationDidReceiveMemoryWarningNotification respectively. Both are left unwired here,
// but the two platforms are NOT equally blocked:
//
//   iOS    — no native code needed. RN core already bridges the memory warning: RCTAppState
//            lists `memoryWarning` in supportedEvents and emits it, and AppState types it
//            (AppStateEvent = 'change' | 'memoryWarning' | 'blur' | 'focus'). Reaching parity
//            with the iOS app is one listener:
//              AppState.addEventListener('memoryWarning', () =>
//                ScreenLogger.logWarning('memory_pressure', {level: 'didReceiveMemoryWarning'}));
//
//   Android — needs a native module. AppStateModule.kt emits only `appStateDidChange` and
//            `appStateFocusChange`; nothing forwards onTrimMemory / onLowMemory to JS, so
//            matching the Android app's `level` field and `low_memory` requires a bridge.

let started = false;
let current: AppStateStatus = AppState.currentState;

export const startLifecycleLogging = (): void => {
  if (started) {
    return;
  }
  started = true;
  AppState.addEventListener('change', (next: AppStateStatus) => {
    const wasBackground = current === 'background' || current === 'inactive';
    if (wasBackground && next === 'active') {
      ScreenLogger.logInfo('app_open', {trigger: 'appstate_active'});
    } else if (current === 'active' && next === 'background') {
      ScreenLogger.logInfo('app_close', {trigger: 'appstate_background'});
    }
    current = next;
  });
};
