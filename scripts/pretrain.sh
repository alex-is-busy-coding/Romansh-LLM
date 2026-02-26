#!/usr/bin/env bash
# Run continued pretraining (QLoRA) with config. Run from repo root.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="${CONFIG:-configs/prod.yaml}"
uv run romansh-llm-pretrain --config "$CONFIG"
