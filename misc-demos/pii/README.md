# PII Scrubbing — Regex Reference

Reference configuration and validation artifacts for scrubbing sensitive values from logs using bitdrift's `regex_match_and_substitute_field` filter.

## What's here

| File | Description |
|------|-------------|
| `regex.yaml` | bitdrift filter configuration applying the PII regex via `regex_match_and_substitute_field` |
| `regex-changes.md` | Documented changes to the regex and the reasoning behind each one |
| `regex-validation.md` | Test cases and expected match/no-match behavior |
| `results/post.jsonl` | Raw validation output |
| `plan.md` | Original requirements and context |

## What the regex matches

The regex targets common secret and token patterns in log field values:

- `Authorization: Bearer <token>` and `Proxy-Authorization: Bearer <token>` headers
- Named token fields: `access_token`, `refresh_token`, `auth_token`, `id_token`, `session_token`, `api_key`, `secret`
- Device identifiers: `device_id`, `client_device_id`, `oai_device_id`
- Raw `Bearer <token>` strings
- JWT tokens (`eyJ...`)
- Custom token prefixes: `encdvc_`, `ua-`
- UUID-formatted values

## Key change from baseline

The `secret` field was separated from the shared character class and given its own line with an expanded value charset (`! @ # $ % ^ & *`) to correctly match passwords and secrets containing special characters. See `regex-changes.md` for details.

## Usage

Apply `regex.yaml` to your bitdrift organization via the dashboard or API. The filter runs server-side and substitutes matched values before logs are stored.
