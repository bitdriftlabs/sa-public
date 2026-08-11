#!/bin/bash
# Ensures a Docker daemon is reachable before any docker/docker compose command runs.
# On macOS this repo is set up against Colima, not Docker Desktop — see
# README.md#prerequisites-macos. Meant to be sourced/called at the top of every
# script here that talks to Docker, so a cold machine gets one clear fix instead
# of a raw "Cannot connect to the Docker daemon" error from whichever command
# happened to run first.
set -e

if docker info >/dev/null 2>&1; then
    exit 0
fi

if [[ "$(uname -s)" == "Darwin" ]] && command -v colima >/dev/null 2>&1; then
    echo "Docker daemon not reachable — starting Colima..."
    colima start
    if ! docker info >/dev/null 2>&1; then
        echo "Colima started but Docker still isn't reachable — run 'colima status' to check." >&2
        exit 1
    fi
    exit 0
fi

echo "Docker daemon not reachable." >&2
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "This repo uses Colima on macOS (not Docker Desktop) — see README.md#prerequisites-macos:" >&2
    echo "  brew install colima docker docker-compose && colima start" >&2
else
    echo "Start your Docker daemon and try again." >&2
fi
exit 1
