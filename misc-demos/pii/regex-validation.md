# PII Scrubbing Regex — Validation

This regex is used to scrub PII and sensitive credentials from log lines before transmission or storage. It is **not** a network path filter.

## What It Matches

| Pattern | Example |
|---|---|
| `Authorization`/`Proxy-Authorization` bearer headers | `Authorization: Bearer eyJ...` |
| Key=value credential fields (`access_token`, `refresh_token`, `auth_token`, `id_token`, `session_token`, `bearer`, `api_key`, `secret`) | `access_token=abcdefghijklmnop` |
| Device ID fields (`device_id`, `client_device_id`, `oai_device_id`) | `device_id=abc-123-def-456` |
| Bare `Bearer` token | `Bearer ghp_abc123...` |
| Raw JWTs (three base64url segments) | `eyJhbGci....eyJzdWIi....SflKxw...` |
| `encdvc_` prefixed tokens | `encdvc_aabbccddeeff...` |
| `ua-` prefixed IDs | `ua-00112233aabb...` |
| UUIDs | `550e8400-e29b-41d4-a716-446655440000` |

Values shorter than 8 characters are intentionally excluded to avoid false positives on short field names or enum values.

## How It Was Tested

The regex was validated against Rust's [`regex`](https://docs.rs/regex) crate (v1.x) using a dedicated regex validator binary.

All test inputs are **synthetic** — structurally realistic but not real credentials or personal data.

```bash
cargo run --bin test_regex
```

### Test Cases

#### Auth headers
| Input | Expected | Label |
|---|---|---|
| `Authorization: Bearer eyJhbGci...` | match | auth header bearer token |
| `Proxy-Authorization: Bearer eyJhbGci...` | match | proxy-authorization header |
| `authorization=bearer dGhpcyBpcyBhIHRlc3QgdG9rZW4xMjM0NTY3OA==` | match | auth header = syntax |

#### Key=value credential fields
| Input | Expected | Label |
|---|---|---|
| `access_token=ya29.A0ARrdaM-fakeGoogleOAuthToken123456789abcdefghijklmno` | match | Google-style OAuth access token |
| `refresh_token=1//0gFakeRefreshTokenXYZabcdefghijklmnopqrstuvwxyz` | match | OAuth refresh token |
| `auth_token: xoxb-fake-slack-bot-token-abcdefghijklmnopqrstuvwxyz` | match | Slack-style auth token |
| `id_token=eyJhbGci...<JWT>` | match | OIDC id_token (JWT) |
| `session_token=AQoXNk5fakeSESSessionTokenABCDEFGHIJKLMNOPQRST` | match | AWS-style session token |
| `api_key='sk-fake1234567890abcdefghijklmnopqrstuvwxyz'` | match | API key with single quotes |
| `api-key: sk-fake1234567890abcdefghijklmnopqrstuvwxyz` | match | api-key hyphen variant |
| `secret=SuperS3cr3tP@ssw0rdForTesting!!` | match | secret field |
| `bearer: fakeTokenValueAbcdef1234567890` | match | lowercase bearer field |

#### Device IDs
| Input | Expected | Label |
|---|---|---|
| `device_id=a1b2c3d4-e5f6-7890-abcd-ef1234567890` | match | device_id UUID format |
| `client_device_id: 3f2504e0-4f89-11d3-9a0c-0305e82c3301` | match | client_device_id UUID |
| `oai_device_id: abcd1234efgh5678ijkl` | match | oai_device_id alphanumeric |
| `client-device-id=550e8400e29b41d4a716446655440000` | match | client-device-id hex string |

#### Bare Bearer tokens
| Input | Expected | Label |
|---|---|---|
| `Bearer ghp_fakeGitHubPersonalAccessToken1234567890abcdef` | match | GitHub PAT style |
| `Bearer sk-proj-fakeOpenAIKeyABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890` | match | OpenAI-style |
| `BEARER ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890` | match | uppercase BEARER |

#### Raw JWTs
| Input | Expected | Label |
|---|---|---|
| `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIi...` | match | standard JWT (HS256) |
| `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImZha2Uta2lkLTEyMyJ9.eyJzdWIi...` | match | RS256 JWT with kid |

#### encdvc_ tokens
| Input | Expected | Label |
|---|---|---|
| `encdvc_deadbeefcafebabe0011223344556677` | match | 32 hex chars |
| `encdvc_0000000000000000000000000000000000000000` | match | 40 hex chars |

#### ua- prefixed IDs
| Input | Expected | Label |
|---|---|---|
| `ua-deadbeef-cafe-babe-0011-223344556677` | match | UUID-like format |
| `ua-00112233aabbccddeeff001122334455` | match | long hex id |

#### UUIDs
| Input | Expected | Label |
|---|---|---|
| `3f2504e0-4f89-11d3-9a0c-0305e82c3301` | match | UUID v1 |
| `6ba7b810-9dad-11d1-80b4-00c04fd430c8` | match | UUID v1 (namespace) |
| `550e8400-e29b-41d4-a716-446655440000` | match | UUID v4 well-known |
| `f47ac10b-58cc-4372-a567-0e02b2c3d479` | match | UUID v4 |

#### Negative cases (must not match)
| Input | Expected | Label |
|---|---|---|
| `hello world this is a normal log line` | no match | plain text |
| `user clicked button` | no match | UI event log |
| `error: connection refused` | no match | error message |
| `short=abc` | no match | value too short |
| `token=1234567` | no match | 7 chars, below 8-char threshold |
| `device_id=abc123` | no match | device_id value only 6 chars |
| `api_key=toolong` | no match | api_key value 7 chars, just under limit |
| `ua-1234567` | no match | ua- only 7 chars after prefix |
| `encdvc_abc123` | no match | encdvc_ only 6 hex chars, below 32 |
| `550e8400-e29b-41d4-a716` | no match | partial UUID (missing last segment) |

### Result

```
PASS: regex compiled successfully

39 passed, 0 failed
```

## Regex Flags

- `(?i)` — case-insensitive matching
- `(?x)` — extended mode (whitespace and comments ignored, for readability)
