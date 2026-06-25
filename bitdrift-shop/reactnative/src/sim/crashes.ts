import {NativeModules} from 'react-native';
import {ScreenLogger} from '../utils/logger';

// ─── Crash catalog ──────────────────────────────────────────────────────────────
// A 1:1 port of the Android Crashes.kt catalog (same 20 names) so crash issue groups
// line up across platforms in the dashboard. Each crash has a uniquely named trigger
// function so the JS stack's top frame is distinct (mirrors Android's per-crash top
// frame requirement for distinct issue grouping).
//
// Portability:
//  • JS-portable crashes run in pure JS/TS.
//  • Native signal crashes (SIGSEGV/SIGBUS/SIGABRT/SIGFPE) and the missing-native-lib
//    crash require the BdCrash native module (android/ + ios/). When that module isn't
//    present (app not yet rebuilt), they fall back to a labelled JS error so the app
//    still behaves, just without a true native signal.

type BdCrashNative = {
  nativeSigsegv(): void;
  nativeSigbus(): void;
  nativeSigabrt(): void;
  nativeSigfpe(): void;
  unsatisfiedLink(): void;
  blockMainThread(ms: number): void; // true ANR: blocks the native UI thread
  forceQuit(): void; // hard process exit
};

const BdCrash: BdCrashNative | undefined = NativeModules.BdCrash as BdCrashNative | undefined;

export const hasNativeCrashModule = (): boolean => BdCrash != null;

// ── Main-thread JVM equivalents ─────────────────────────────────────────────────
function crashNullPointer(): void {
  const s: unknown = null;
  // Cannot read properties of null
  return (s as {length: number}).length as unknown as void;
}

function crashArrayIndex(): void {
  const arr: number[] = [1, 2, 3];
  // Out-of-bounds read returns undefined in JS; dereferencing it throws.
  return (arr[99] as unknown as {toFixed: () => void}).toFixed();
}

function crashClassCast(): void {
  const n: unknown = 'hello';
  // "hello".toFixed is not a function — JS analogue of a bad cast.
  return (n as {toFixed: (d: number) => void}).toFixed(2);
}

function crashDivideByZero(): void {
  // Float 1/0 is Infinity (no throw); BigInt division by zero throws RangeError.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const x = BigInt(1) / BigInt(0);
}

function crashNumberFormat(): void {
  // BigInt() on a non-numeric string throws SyntaxError.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const x = BigInt('not-a-number');
}

function crashIllegalState(): void {
  throw new Error('IllegalState: check(false) failed');
}

function crashIllegalArgument(): void {
  throw new Error('IllegalArgument: require(false) failed');
}

function crashConcurrentModification(): void {
  throw new Error('ConcurrentModificationException: list mutated during iteration');
}

function crashStackOverflow(): void {
  const infiniteRecurse = (n: number): number => infiniteRecurse(n + 1);
  infiniteRecurse(0);
}

function crashStringIndex(): void {
  const s = 'hello';
  // Out-of-range char access is undefined; dereferencing throws.
  return (s[999] as unknown as {length: number}).length as unknown as void;
}

function crashNegativeArraySize(): void {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const arr = new Array(-1);
}

function crashAssertionError(): void {
  throw new Error('AssertionError: assertion failed');
}

function crashUnsatisfiedLink(): void {
  if (BdCrash) {
    BdCrash.unsatisfiedLink();
    return;
  }
  throw new Error('UnsatisfiedLinkError: native library not found (no BdCrash module)');
}

// ── Background-thread / async equivalents ────────────────────────────────────────
function crashRuntimeBackgroundThread(): void {
  // Throw outside the React call stack so it reaches the global handler (fatal).
  setTimeout(() => {
    throw new Error('RuntimeException on worker thread');
  }, 0);
}

function crashCoroutineIo(): void {
  // Unhandled async rejection surfaced as an uncaught error.
  setTimeout(() => {
    throw new Error('IllegalState on IO dispatcher (coroutine_io)');
  }, 0);
}

function crashOomAllocatorThread(): void {
  // Grow memory until the JS heap is exhausted.
  const blocks: ArrayBuffer[] = [];
  for (;;) {
    blocks.push(new ArrayBuffer(64 * 1024 * 1024));
  }
}

// ── Native signals (require BdCrash module) ──────────────────────────────────────
function crashNativeSigsegv(): void {
  if (BdCrash) {
    BdCrash.nativeSigsegv();
    return;
  }
  throw new Error('native_sigsegv requested but BdCrash native module is unavailable');
}

function crashNativeSigbus(): void {
  if (BdCrash) {
    BdCrash.nativeSigbus();
    return;
  }
  throw new Error('native_sigbus requested but BdCrash native module is unavailable');
}

function crashNativeSigabrt(): void {
  if (BdCrash) {
    BdCrash.nativeSigabrt();
    return;
  }
  throw new Error('native_sigabrt requested but BdCrash native module is unavailable');
}

function crashNativeSigfpe(): void {
  if (BdCrash) {
    BdCrash.nativeSigfpe();
    return;
  }
  throw new Error('native_sigfpe requested but BdCrash native module is unavailable');
}

// Ordered catalog — same order and names as Android's Crashes.all.
export const CRASHES: ReadonlyArray<{name: string; fn: () => void}> = [
  // Main-thread JVM
  {name: 'null_pointer', fn: crashNullPointer},
  {name: 'array_index', fn: crashArrayIndex},
  {name: 'class_cast', fn: crashClassCast},
  {name: 'divide_by_zero', fn: crashDivideByZero},
  {name: 'number_format', fn: crashNumberFormat},
  {name: 'illegal_state', fn: crashIllegalState},
  {name: 'illegal_argument', fn: crashIllegalArgument},
  {name: 'concurrent_modification', fn: crashConcurrentModification},
  {name: 'stack_overflow', fn: crashStackOverflow},
  {name: 'string_index', fn: crashStringIndex},
  {name: 'negative_array_size', fn: crashNegativeArraySize},
  {name: 'assertion_error', fn: crashAssertionError},
  {name: 'unsatisfied_link', fn: crashUnsatisfiedLink},
  // Background-thread / async JVM
  {name: 'runtime_background_thread', fn: crashRuntimeBackgroundThread},
  {name: 'coroutine_io', fn: crashCoroutineIo},
  {name: 'oom_allocator_thread', fn: crashOomAllocatorThread},
  // Native signals
  {name: 'native_sigsegv', fn: crashNativeSigsegv},
  {name: 'native_sigbus', fn: crashNativeSigbus},
  {name: 'native_sigabrt', fn: crashNativeSigabrt},
  {name: 'native_sigfpe', fn: crashNativeSigfpe},
];

export const CRASH_NAMES: ReadonlyArray<string> = CRASHES.map(c => c.name);

export const crashByName = (name: string): (() => void) | undefined =>
  CRASHES.find(c => c.name === name)?.fn;

// Fire a crash by name. Logs the `about_to_crash` breadcrumb + `crash_kind` field first
// (matches Android), then triggers. Synchronous JS crashes are dispatched on the next
// tick so they escape React's render/event try-catch and become fatal/global.
export const triggerCrash = (name: string): void => {
  const fn = crashByName(name);
  if (!fn) {
    return;
  }
  ScreenLogger.addField('crash_kind', name);
  ScreenLogger.logWarning(`about_to_crash: ${name}`, {crash_kind: name});
  setTimeout(() => {
    fn();
  }, 300); // ~300ms flush window mirrors Android's CRASH_FLUSH_MS
};

// ── ANR (best-effort) ────────────────────────────────────────────────────────────
// A true ANR requires blocking the native UI thread, which only the native module can
// do. Without it, we block the JS thread (freezes all interaction the JS thread drives)
// as a degraded approximation.
export const triggerAnr = (blockMs: number): void => {
  if (BdCrash) {
    BdCrash.blockMainThread(blockMs);
    return;
  }
  const end = Date.now() + blockMs;
  while (Date.now() < end) {
    // Busy-wait: degraded ANR approximation when the native module is absent.
  }
};

// ── Force quit ───────────────────────────────────────────────────────────────────
export const triggerForceQuit = (): void => {
  if (BdCrash) {
    BdCrash.forceQuit();
    return;
  }
  // No portable JS way to kill the process; throw fatally as the closest fallback.
  setTimeout(() => {
    throw new Error('force_quit requested but BdCrash native module is unavailable');
  }, 0);
};
