#!/usr/bin/env bash
# Single entrypoint for local Docker and SageMaker
# When SM_MODEL_DIR is set, use config channel; else use CMD.
set -e
if [[ -n "${SM_MODEL_DIR:-}" ]]; then
  exec /app/scripts/sagemaker_train.sh
fi
exec romansh-llm-pretrain "$@"
