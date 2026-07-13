#!/usr/bin/env bash
set -euo pipefail
python3 /workspace/shared_scripts/setup_task.py --task-json /workspace/tasks/forced_perspective_moving_day_seed_0001/task.json
exec /workspace/shared_scripts/open_puzzle_browser.sh
