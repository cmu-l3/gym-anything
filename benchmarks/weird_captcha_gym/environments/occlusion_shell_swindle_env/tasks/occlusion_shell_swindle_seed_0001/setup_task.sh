#!/usr/bin/env bash
set -euo pipefail

python3 /workspace/shared_scripts/setup_task.py --task-json /workspace/tasks/occlusion_shell_swindle_seed_0001/task.json
exec /workspace/shared_scripts/open_puzzle_browser.sh
