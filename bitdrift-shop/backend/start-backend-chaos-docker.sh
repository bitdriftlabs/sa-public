#!/bin/bash
set -e
docker compose down
TAG=${1:-latest} CHAOS_MODE=1 docker compose up --pull always
