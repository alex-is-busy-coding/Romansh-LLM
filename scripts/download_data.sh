#!/usr/bin/env bash
# Cache ZurichNLP/quotidiana from Hugging Face (raw data).
# Run from repo root. Optional: set HF_HOME or use default cache.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Caching ZurichNLP/quotidiana (subsets 1997_2008, 2021_2025)..."
uv run python -c "
from datasets import load_dataset
for subset in ['1997_2008', '2021_2025']:
    load_dataset('ZurichNLP/quotidiana', subset, split='train')
    print(f'  Cached {subset}')
print('Done.')
"
