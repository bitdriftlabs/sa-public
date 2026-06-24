#!/bin/bash
set -e
docker compose -f docker-compose.yml -f docker-compose.o11y.yml down
TAG=${1:-latest} docker compose -f docker-compose.yml -f docker-compose.o11y.yml up --pull always
