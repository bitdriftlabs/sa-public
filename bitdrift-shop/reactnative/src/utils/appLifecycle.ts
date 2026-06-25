import {AppState, type AppStateStatus} from 'react-native';
import {ScreenLogger} from './logger';

// Foreground/background lifecycle events, mirroring the Android app's
// AppLifecycleCallbacks (app_open / app_close). React Native's AppState is the
// cross-platform equivalent of Android's activity start/stop callbacks.
//
// Note on memory events: the Android app also emits `memory_pressure` / `low_memory`
// from ComponentCallbacks2.onTrimMemory / onLowMemory. React Native core exposes no
// cross-platform memory-pressure signal, so those require a native hook (Android
// onTrimMemory, iOS didReceiveMemoryWarning) and are intentionally left unwired here.

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
