# Appendix

Troubleshooting notes for issues that don't fit neatly into the main [README](README.md) quick-start flow.

## Colima can't see an external-drive checkout (`otel-collector` crash-loops)

If your `opentelemetry-demo` clone lives outside `$HOME` — e.g. on an external drive like `/Volumes/external` — Colima's VM may not have it mounted at all. Docker still lets you `docker run`/`docker compose up` with bind mounts pointing into that path, but since the VM can't see the real files, it silently substitutes empty directories for them instead of failing outright.

**Symptom:** `otel-collector` (and potentially other services with config bind-mounts) restart forever. `docker logs otel-collector` shows something like:

```
Error: failed to get config: cannot resolve the configuration: cannot retrieve the configuration: unable to read the file file:/etc/otelcol-config.yml: read /etc/otelcol-config.yml: is a directory
```

**Confirm it's a Colima mount issue:**

```bash
colima ssh -- mount | grep -i virtiofs
```

If the path your checkout lives under (e.g. `/Volumes/external`) isn't listed, the VM doesn't have it.

**Fix** — add the path to Colima's mounts and restart the VM:

```bash
colima stop
colima start --mount /Volumes/external:w
```

This restarts the whole VM: containers with `restart: unless-stopped` (the OTel Demo stack) come back on their own, but `clickstack` does not and must be relaunched manually (see [Prerequisites](README.md#prerequisites-macos) in the main README).

**Make it permanent** so the mount survives future `colima start`s without the flag — add it to `~/.colima/default/colima.yaml`:

```yaml
mounts:
  - location: /Volumes/external
    writable: true
```

## `astronomy-db` missing `astronomy_user` (product-catalog crash-loops, no product images)

A follow-on effect of the bug above: `astronomy-db` bind-mounts `src/postgresql/init.sql` to create the `astronomy_user` role and `astronomy_db` database on its **first** boot only. If that first boot happened while Colima couldn't see the external volume, `init.sql` looked like an empty directory, so Postgres's init-script step silently found nothing to run — and once a Postgres data directory exists, it never re-runs init scripts against it, even after the mount is fixed.

**Symptom:** `product-catalog` restarts forever with no product images in the app and no traces for it. Confirm with:

```bash
docker exec astronomy-db psql -U postgres -c "\du"    # astronomy_user missing from role list
```

**Fix** — wipe the stale Postgres volume so it reinitializes from the now-correct `init.sql`:

```bash
docker stop astronomy-db
docker rm -v astronomy-db
docker compose -f compose.yaml up -d astronomy-db
```

`product-catalog` is `restart: unless-stopped`, so it retries on its own and recovers once `astronomy-db` reports healthy (~15-20s) — no need to touch it directly.

## Android app has no product images, no crash, no obvious error

`build.gradle.kts` defaults `OTEL_DEMO_PORT` to `8081` (the real OTel Demo backend), so a clean checkout without any `.local.properties` override works out of the box. But if you've explicitly set `OTEL_DEMO_PORT` somewhere — `.local.properties`, a shell env var, CI config — and mistype or copy-paste the wrong value (e.g. `8080`), the symptom is worth knowing because it's easy to misdiagnose:

If the backend is confirmed healthy (product API returns data via `curl`/browser, containers healthy) but the app still shows no product images and no data on Browse/Featured/Product Detail, check what port the app actually built against **before** looking at the backend at all:

```bash
grep OTEL_DEMO android/.local.properties android/local.properties 2>/dev/null
```

Port `8080` happens to be ClickStack/HyperDX's own web UI (see [Set up ClickStack](README.md#1-set-up-clickstack)), not the OTel Demo backend — so a request that lands there instead gets 404s or hangs on "Loading...", with **zero** matching log lines in `frontend`'s or `product-catalog`'s container logs, because the request never reaches the OTel Demo stack at all. Every infra-side check (container health, direct `curl` to the real backend, Colima mounts) comes back clean, since the bug is entirely in what port the client is configured to hit.

**Fix:** correct (or remove) the `OTEL_DEMO_PORT` override so it resolves to `8081`, then rebuild and reinstall (`./gradlew :app:installDebug`) — `BuildConfig` values are baked in at build time, so editing `.local.properties` alone does nothing until you rebuild.

**To confirm this is the issue** before touching the backend: check `android/app/build/generated/source/buildConfig/debug/.../BuildConfig.java` for the actual baked-in `OTEL_DEMO_PORT`, or open `http://10.0.2.2:8081/api/products?currencyCode=USD` directly in the emulator's browser (`adb shell am start -a android.intent.action.VIEW -d "..."`) — if that succeeds but the app doesn't, the app isn't hitting the URL you think it is.

## Auditing the whole stack after a Colima mount fix

Fixing the Colima mount only repairs what containers see *going forward* — anything that already baked incorrect state into a persistent volume (like `astronomy-db` above) stays broken until that volume is wiped. After any Colima mount change, audit the full stack rather than waiting for the next silent failure:

1. **List every host bind mount in the stack:**

   ```bash
   awk '
   /^  [a-zA-Z0-9_-]+:$/ { svc=$1 }
   /volumes:/ { invol=1; print "== " svc " (line " NR ") =="; next }
   invol && /^      - / { print "   ", $0; next }
   invol && !/^      - / { invol=0 }
   ' compose.yaml
   ```

2. **Confirm each mounted path resolves to real content, not an auto-vivified empty directory.** Most OTel Demo images are distroless (no shell), so `docker exec ... ls` won't work — mount the same host path into a throwaway `busybox` container instead:

   ```bash
   docker run --rm -v <host_path>:<container_path>:ro busybox ls -la <container_path>
   ```

   An empty directory where a file should be means the mount was broken when that path was first read.

3. **Flag the dangerous combination: a bind-mounted init/config file paired with a persistent volume.** A plain read-every-start bind mount (`flagd`, `flagd-ui`, `otel-collector`'s configs, `product-catalog`'s `otel-config.yml`) self-heals the moment the mount is fixed — just restart the container. A service that only *seeds* a persistent volume from that file on first boot (`astronomy-db` → `/var/lib/postgresql`) does not self-heal; a bad first boot bakes itself in until the volume is wiped. Cross-reference bind mounts against `docker inspect <container> --format '{{json .Mounts}}'` for any `"Type": "volume"` entries on the same service.

4. **For every service with that combination, verify the expected first-boot artifact actually exists** — don't just check that the container is `Up (healthy)`, since a healthcheck can pass while the app runs against an empty/default state. For `astronomy-db` that means checking `\du`/`\l` for the expected role and database; for other stateful services, check for their equivalent (seeded rows, created indices, expected config keys, etc.).

## Fully purging ClickStack / HyperDX

The main README notes the `clickstack` container has "no persistence" because it's run without an explicit `-v` volume flag — but the `docker.hyperdx.io/hyperdx/hyperdx-all-in-one` image declares an internal `VOLUME` for `/var/lib/clickhouse`, so Docker silently creates an **anonymous volume** for it. A plain `docker stop`/`docker rm` leaves that volume behind, so old (possibly corrupted) ClickHouse state can survive what looks like a full reset.

**Symptom:** HyperDX UI errors like `Failed to fetch` on `DESCRIBE default.otel_logs`, or traces/logs missing even after restarting the container.

**Fully purge and start clean:**

```bash
docker stop clickstack
docker rm -v clickstack        # -v removes the anonymous ClickHouse data volume too
docker volume ls | grep -i clickhouse   # sanity check — should print nothing
```

Then relaunch it fresh (same command as the main README's ClickStack step):

```bash
docker run -d --name clickstack -p 8080:8080 -p 4317:4317 -p 4318:4318 docker.hyperdx.io/hyperdx/hyperdx-all-in-one
```

This gives a brand-new ClickHouse instance — you'll need to sign up again and grab a new API key (see [Set up ClickStack](README.md#1-set-up-clickstack) in the main README).
