# PII Scrubbing Regex — Change Summary

## Changes Made

### 1. `secret` field — expanded value character class

**Problem:** The original character class `[A-Za-z0-9._~+/=-]` does not include common password characters like `@`, `!`, `#`, `$`, etc. A secret value like `SuperS3cr3tP@ssw0rdForTesting!!` would only match up to the `@`, leaking the remainder in the log message.

**Before:**
```
| (?:access[_-]?token|...|secret)\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{8,}
```

**After:**
```
| secret\s*[:=]\s*(?:"[A-Za-z0-9._~+/=!@#$%^&*-]{8,}"|'[A-Za-z0-9._~+/=!@#$%^&*-]{8,}'|[A-Za-z0-9._~+/=!@#$%^&*-]{8,})
```

`secret` is now on its own line with a wider value charset covering `! @ # $ % ^ & *`, which covers the majority of common password special characters.

---

### 2. Quoted values — closing quote not captured

**Problem:** The original pattern used `["']?` to optionally match an opening quote, then matched the value with `[A-Za-z0-9._~+/=-]{8,}`. Because the quote character is not in the value class, a pattern like `api_key='sk-...'` would match and redact everything up to (but not including) the closing `'`, leaving a stray `'` visible in the output:

```
openai config: <redacted>'
```

**Before:**
```
["']?[A-Za-z0-9._~+/=-]{8,}
```

**After:**
```
(?:"[A-Za-z0-9._~+/=-]{8,}"|'[A-Za-z0-9._~+/=-]{8,}'|[A-Za-z0-9._~+/=-]{8,})
```

The fix uses symmetric alternation: if an opening quote is present, the same quote character is required at the end of the value, consuming both. If no quote is present, the bare value is matched as before. This fix is applied to all `key=value` credential and device ID patterns.

---

## Known Limitation — Structured Field Values

The `name: ''` transform applies only to the **log message string**. Sensitive values that are emitted as **structured log fields** (key-value pairs in the fields map) are only redacted if their bare value independently matches a pattern — for example, a raw JWT, a UUID, a `Bearer <token>`, or an `encdvc_` token.

Field values like `access_token`, `refresh_token`, `api_key`, `secret`, `auth_token`, `session_token`, and `bearer` are **not** redacted when stored as structured fields, because the regex runs against the message text, not field values.

For example, this field value will appear in plaintext in the structured fields:
```json
"access_token": "ya29.A0ARrdaM-fakeGoogleOAuthToken123456789abcdefghijklmno"
```

**To address this**, add a separate `regex_match_and_substitute_field` transform per sensitive field name, using the field's `name` property and a bare-value pattern. Example:

```yaml
- regex_match_and_substitute_field:
    name: 'access_token'
    pattern: '.+'
    substitution: <redacted>
- regex_match_and_substitute_field:
    name: 'refresh_token'
    pattern: '.+'
    substitution: <redacted>
# ... repeat for: auth_token, id_token, session_token, bearer, api_key, api-key, secret
```

This is a structural gap in the current configuration that the message-level regex cannot close.

---

## Updated Regex

```
(?ix)
(
  (?:authorization|proxy-authorization)\s*[:=]\s*bearer\s+[A-Za-z0-9._~+/=-]{8,}
  | (?:access[_-]?token|refresh[_-]?token|auth[_-]?token|id[_-]?token|session[_-]?token|bearer|api[_-]?key)\s*[:=]\s*(?:"[A-Za-z0-9._~+/=-]{8,}"|'[A-Za-z0-9._~+/=-]{8,}'|[A-Za-z0-9._~+/=-]{8,})
  | secret\s*[:=]\s*(?:"[A-Za-z0-9._~+/=!@#$%^&*-]{8,}"|'[A-Za-z0-9._~+/=!@#$%^&*-]{8,}'|[A-Za-z0-9._~+/=!@#$%^&*-]{8,})
  | (?:device[_-]?id|client[_-]?device[_-]?id|oai[_-]?device[_-]?id)\s*[:=]\s*(?:"[A-Za-z0-9._:-]{8,}"|'[A-Za-z0-9._:-]{8,}'|[A-Za-z0-9._:-]{8,})
  | Bearer\s+[A-Za-z0-9._~+/=-]{8,}
  | eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}
  | encdvc_[0-9a-f]{32,}
  | ua-[0-9a-fA-F-]{8,}
  | [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}
)
```
