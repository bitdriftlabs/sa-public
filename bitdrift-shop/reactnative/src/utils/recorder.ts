import {Platform} from 'react-native';

/**
 * Record mode for the test harness (debug builds only). The app can't write files without a
 * native module and can't take launch arguments without native code, so it talks to the local
 * collector that `test.sh` starts (tools/conformance/collector.py):
 *   GET  /config  -> {runs, seed, persona}: when answered, the app autoruns and records
 *   POST /record  -> JSONL records, same shapes as the native recorders
 * With no collector running the config request fails fast and the app behaves as before.
 */
const PORT = 5599;
const HOST = Platform.OS === 'android' ? '10.0.2.2' : 'localhost';
const BASE = `http://${HOST}:${PORT}`;

export type AutorunConfig = {runs: number; seed: number; persona: string};

type Fields = Record<string, unknown> | undefined;

let recording = false;
let queue: string[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;
let flushing: Promise<void> = Promise.resolve();

type OpenSpan = {name: string; parent: string | null; fields: Record<string, string> | null};
const openSpans = new Map<string, OpenSpan>();

const SPAN_KEYS = new Set(['_span_id', '_span_type', '_result', '_duration_ms', 'parent_span_id']);

const stringify = (fields: Fields): Record<string, string> | null => {
  if (!fields) {
    return null;
  }
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (!SPAN_KEYS.has(k)) {
      out[k] = String(v);
    }
  }
  return Object.keys(out).length > 0 ? out : null;
};

const enqueue = (rec: Record<string, unknown>) => {
  queue.push(JSON.stringify({t: Date.now(), ...rec}));
  if (!flushTimer) {
    flushTimer = setTimeout(() => {
      flushTimer = null;
      void flush();
    }, 100);
  }
};

const flush = (): Promise<void> => {
  flushing = flushing.then(async () => {
    if (queue.length === 0) {
      return;
    }
    const body = queue.join('\n');
    queue = [];
    try {
      await fetch(`${BASE}/record`, {method: 'POST', body});
    } catch {
      // The collector going away must never affect the app.
    }
  });
  return flushing;
};

/** Debug builds only: ask the collector whether to autorun. Resolves null quickly when it isn't there. */
export const fetchAutorunConfig = async (): Promise<AutorunConfig | null> => {
  if (!__DEV__) {
    return null;
  }
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 1500);
    const res = await fetch(`${BASE}/config`, {signal: ctl.signal});
    clearTimeout(timer);
    return res.ok ? ((await res.json()) as AutorunConfig) : null;
  } catch {
    return null;
  }
};

export const startRecording = () => {
  recording = true;
  // Carry over spans that were already open so their later ends still match a start.
  for (const [id, s] of openSpans) {
    enqueue({kind: 'span_start', id, name: s.name, parent: s.parent, carried: true, fields: s.fields});
  }
};

export const flushRecording = (): Promise<void> => flush();

/** Called from the ScreenLogger log functions: one hook covers logs and the paired-log span shim. */
export const recordLog = (level: string, message: string, fields: Fields) => {
  const type = fields?._span_type as string | undefined;
  const id = fields?._span_id as string | undefined;
  if (type === 'start' && id) {
    const parent = (fields?.parent_span_id as string | undefined) ?? null;
    const flat = stringify(fields);
    openSpans.set(id, {name: message, parent, fields: flat});
    if (recording) {
      enqueue({kind: 'span_start', id, name: message, parent, fields: flat});
    }
    return;
  }
  if (type === 'end' && id) {
    openSpans.delete(id);
    if (recording) {
      enqueue({kind: 'span_end', id, name: message, result: fields?._result ?? 'success', fields: stringify(fields)});
    }
    return;
  }
  if (recording) {
    enqueue({kind: 'log', level, message, fields: stringify(fields)});
  }
};

export const recordScreen = (name: string) => {
  if (recording) {
    enqueue({kind: 'screen', name});
  }
};
