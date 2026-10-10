#!/usr/bin/env bash
# Thin wrapper kept for convenience. The real build (Neutron Clang, no GCC) lives in ci/build.sh.
exec "$(dirname "$0")/ci/build.sh" "$@"
