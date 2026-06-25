import {
  logScreenView as bdLogScreenView,
  trace as bdTrace,
  debug as bdDebug,
  info as bdInfo,
  warn as bdWarn,
  error as bdError,
  addField as bdAddField,
  removeField as bdRemoveField,
  setEntityId as bdSetEntityId,
  setFeatureFlagExposure as bdSetFeatureFlagExposure,
} from '@bitdrift/react-native';

// Centralised logger that writes to both console (local) and bitdrift (remote).
// Fields are always Record<string, string> so they serialise cleanly as bitdrift
// structured fields. Numbers should be converted by the caller via String().
//
// This is the single source of truth for every bitdrift Capture SDK call in the
// app, mirroring the Android app's ScreenLogger + Logger usage. Where the React
// Native SDK lacks an API the Android SDK has, we approximate it here and mark it
// clearly (see setEntityId and the Spans section).

type Fields = Record<string, string>;

const formatConsole = (level: string, message: string, fields?: Fields): string => {
  if (!fields || Object.keys(fields).length === 0) {
    return `[${level}] ${message}`;
  }
  const sorted = Object.entries(fields)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join(' | ');
  return `[${level}] ${message} | ${sorted}`;
};

// ─── Spans (approximation) ────────────────────────────────────────────────────
// The React Native SDK has no span API. The Android app uses Logger.startSpan /
// trackSpan, which (per bitdrift docs) each emit a start and an end log carrying
// `_duration_ms`. We reproduce that exact data shape with paired logs correlated by
// `_span_id`, so the dashboard sees the same queryable signal (name + _duration_ms
// + _result, optionally nested via parent_span_id).
export type SpanResult = 'success' | 'failure' | 'canceled';

export type Span = {
  readonly id: string;
  end: (result?: SpanResult, endFields?: Fields) => void;
};

let spanCounter = 0;
const nowMs = (): number => Date.now();

export const ScreenLogger = {
  // ── Screen Views ────────────────────────────────────────────────────────────
  logScreenView: (screenName: string) => {
    console.log(`_screen_name: ${screenName}`);
    bdLogScreenView(screenName);
  },

  // ── Custom logs ───────────────────────────────────────────────────────────────
  logTrace: (message: string, fields?: Fields) => {
    console.log(formatConsole('TRACE', message, fields));
    bdTrace(message, fields);
  },

  logDebug: (message: string, fields?: Fields) => {
    console.log(formatConsole('DEBUG', message, fields));
    bdDebug(message, fields);
  },

  logInfo: (message: string, fields?: Fields) => {
    console.log(formatConsole('INFO', message, fields));
    bdInfo(message, fields);
  },

  logWarning: (message: string, fields?: Fields) => {
    console.warn(formatConsole('WARNING', message, fields));
    bdWarn(message, fields);
  },

  // The RN SDK's error() signature is error(message, error?, fields?) — the second
  // arg is the captured exception. Pass a real Error when available so the stack is
  // attached in the dashboard (matches Android's logError(..., throwable = e)).
  logError: (message: string, fields?: Fields, err?: unknown) => {
    console.error(formatConsole('ERROR', message, fields));
    const errorObj = err instanceof Error ? err : err != null ? new Error(String(err)) : null;
    bdError(message, errorObj, fields);
  },

  // ── Global fields ─────────────────────────────────────────────────────────────
  addField: (key: string, value: string) => {
    bdAddField(key, value);
  },

  removeField: (key: string) => {
    bdRemoveField(key);
  },

  // ── Entity ID ─────────────────────────────────────────────────────────────────
  // Native entity API (available since @bitdrift/react-native 0.12.x), matching the
  // Android app's Logger.setEntityId().
  setEntityId: (entity: string) => {
    bdSetEntityId(entity);
  },

  // ── Feature flag exposures ──────────────────────────────────────────────────────
  setFeatureFlagExposure: (name: string, variant: string) => {
    bdSetFeatureFlagExposure(name, variant);
  },

  // ── Spans ───────────────────────────────────────────────────────────────────────
  startSpan: (name: string, fields?: Fields, parentSpanId?: string): Span => {
    spanCounter += 1;
    const id = `span_${spanCounter}_${nowMs()}`;
    const startedAt = nowMs();
    ScreenLogger.logInfo(name, {
      ...(fields ?? {}),
      _span_id: id,
      _span_type: 'start',
      ...(parentSpanId ? {parent_span_id: parentSpanId} : {}),
    });
    return {
      id,
      end: (result: SpanResult = 'success', endFields?: Fields) => {
        const durationMs = nowMs() - startedAt;
        ScreenLogger.logInfo(name, {
          ...(endFields ?? {}),
          _span_id: id,
          _span_type: 'end',
          _result: result,
          _duration_ms: String(durationMs),
          ...(parentSpanId ? {parent_span_id: parentSpanId} : {}),
        });
      },
    };
  },

  // Synchronous wrapper: starts a span, runs fn, ends with success/failure.
  trackSpan: <T,>(name: string, fields: Fields | undefined, fn: () => T): T => {
    const span = ScreenLogger.startSpan(name, fields);
    try {
      const result = fn();
      span.end('success');
      return result;
    } catch (e) {
      span.end('failure');
      throw e;
    }
  },

  // ── Simulation lifecycle helpers (kept from the original logger) ─────────────────
  logSimulationStart: (totalRuns: number) => {
    ScreenLogger.logInfo('simulation_start', {total_runs: String(totalRuns)});
  },

  logSimulationEnd: (completedRuns: number) => {
    ScreenLogger.logInfo('simulation_end', {total_runs: String(completedRuns)});
  },
};
