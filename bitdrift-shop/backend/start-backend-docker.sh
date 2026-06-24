#!/bin/bash
set -e
docker compose down
TAG=${1:-latest} docker compose up --pull always
