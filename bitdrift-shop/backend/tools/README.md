# backend/tools

Occasional scripts. Nothing here is needed for normal use — for that, see
[`../start-backend-docker.sh`](../start-backend-docker.sh) and
[`../start-backend-chaos-docker.sh`](../start-backend-chaos-docker.sh).

Run them from anywhere; each resolves its own paths.

## Backend development

Build from source instead of pulling the published image:

```bash
./build.sh              # build stevelerner/bitdrift-shop-backend:latest
./build.sh v1.0.0       # tagged build
./run.sh                # run the locally built image, without compose
./docker-cleanup.sh     # remove the container and free port 5173
```

Publish:

```bash
./dockerhub-push.sh          # push latest
./dockerhub-push.sh v1.0.0   # tag and push a version
```

## Observability variant

```bash
docker network create tinyolly-network   # once
./start-backend-docker-o11y.sh
```

Attaches the container to the external `tinyolly-network` so it can reach a local
OpenTelemetry collector. Applies `../docker-compose.o11y.yml` as an override on
top of the standard compose file.

## Stopping

```bash
./stop-backend-docker.sh
```

Rarely needed: the start scripts run in the foreground so Ctrl-C stops them, and
each runs `docker compose down` before starting.

## Housekeeping

```bash
./cleanup.sh            # remove venv/, __pycache__/, *.pyc from the backend root
./ensure-docker.sh      # verify the Docker daemon is reachable (Colima-aware)
```

`ensure-docker.sh` is called automatically by the start and build scripts; you
shouldn't need to run it yourself.

## Regenerating product images

The 18 images in `../images/` are committed, so this is only for refreshing them
with new photos from [Pexels](https://www.pexels.com/api/):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install Pillow

PEXELS_API_KEY=<your-key> python generate_images.py
```

Searches Pexels per product, downloads the top result, center-crops to square and
resizes to 400×400, falling back to a grey placeholder with the product's initials
if a search fails. Writes to `../images/`.

Rebuild the image afterwards so the new files are included:

```bash
./build.sh
```
