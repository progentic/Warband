#!/usr/bin/env bash
# Validation only; no VM can be provisioned through this wrapper.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export LIMA_HOME="$project_root/.local/lima"
exec limactl validate "$project_root/vm/lima.yaml"
