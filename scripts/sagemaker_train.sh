#!/usr/bin/env bash
# SageMaker training entrypoint
# Run CPT with config from the config channel or default.
set -e
CONFIG="/opt/ml/input/data/config/config.yaml"
[[ -f "$CONFIG" ]] || CONFIG="/app/configs/prod.yaml"
exec romansh-llm-pretrain --config "$CONFIG"
