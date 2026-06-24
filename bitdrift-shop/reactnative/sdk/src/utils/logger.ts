import {
  logScreenView as bdLogScreenView,
  info,
  warning,
  error,
  debug,
} from '@bitdrift/react-native';

// Centralised logger that writes to both console (local) and bitdrift (remote).
// Fields are always Record<string, string> so they serialise cleanly as bitdrift
// structured fields. Numbers should be converted by the caller via String().

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

export const ScreenLogger = {
  // Workshop 2 — Screen Views
  logScreenView: (screenName: string) => {
    console.log(`_screen_name: ${screenName}`);
    bdLogScreenView(screenName);
  },

  // Workshop 4c — Logging
  logDebug: (message: string, fields?: Fields) => {
    console.log(formatConsole('DEBUG', message, fields));
    debug(message, fields);
  },

  logInfo: (message: string, fields?: Fields) => {
    console.log(formatConsole('INFO', message, fields));
    info(message, fields);
  },

  logWarning: (message: string, fields?: Fields) => {
    console.warn(formatConsole('WARNING', message, fields));
    warning(message, fields);
  },

  logError: (message: string, fields?: Fields) => {
    console.error(formatConsole('ERROR', message, fields));
    error(message, fields);
  },

  logSimulationStart: (totalRuns: number) => {
    ScreenLogger.logInfo('simulation_start', {total_runs: String(totalRuns)});
  },

  logSimulationEnd: (completedRuns: number) => {
    ScreenLogger.logInfo('simulation_end', {completed_runs: String(completedRuns)});
  },
};
