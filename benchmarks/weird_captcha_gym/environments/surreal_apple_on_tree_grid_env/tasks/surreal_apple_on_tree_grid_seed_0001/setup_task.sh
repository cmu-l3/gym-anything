#!/usr/bin/env bash
set -euo pipefail

TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 /workspace/shared_scripts/setup_task.py --task-json "${TASK_DIR}/task.json"
exec /workspace/shared_scripts/open_puzzle_browser.sh
