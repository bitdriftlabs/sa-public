import {Platform} from 'react-native';
import {BITDRIFT_API_KEY as ENV_API_KEY, BITDRIFT_API_HOST as ENV_API_HOST, BACKEND_PORT as ENV_BACKEND_PORT} from '@env';

// ─── bitdrift SDK ────────────────────────────────────────────────────────────
// Set BITDRIFT_API_KEY in your .env file.
// Values are injected at Metro bundle time via react-native-dotenv.
// See README.md § "Configuration" for details.
export const BITDRIFT_API_KEY: string = ENV_API_KEY ?? '';

// Normalise to a full URL — the SDK's generateDeviceCode() needs https://
// so accept both 'api.bitdrift.dev' and 'https://api.bitdrift.dev'.
const _rawApiHost = ENV_API_HOST || undefined;
export const BITDRIFT_API_HOST: string | undefined = _rawApiHost
  ? _rawApiHost.startsWith('http') ? _rawApiHost : `https://${_rawApiHost}`
  : undefined;

// ─── Backend ─────────────────────────────────────────────────────────────────
// Override BACKEND_PORT if your server is running on a different port.
const BACKEND_PORT = ENV_BACKEND_PORT ?? '5173';

// Android emulator reaches the host machine via the special alias 10.0.2.2.
// iOS simulator shares the host network, so 127.0.0.1 works directly.
const BACKEND_HOST = Platform.select({
  android: '10.0.2.2',
  ios: '127.0.0.1',
  default: 'localhost',
});

export const BACKEND_BASE_URL = `http://${BACKEND_HOST}:${BACKEND_PORT}/api`;
