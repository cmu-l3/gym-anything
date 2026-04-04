#!/usr/bin/env bash
# Setup for fear_conditioning_coder task.
# Removes any pre-existing output file so the agent must create it fresh.
# Ensures PsychoPy is running with the Coder view open.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /workspace/scripts/task_utils.sh

record_task_start

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/fear_conditioning.py

# Ensure output directories exist
mkdir -p /home/ga/PsychoPyExperiments/data

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    launch_psychopy_builder
    wait_for_psychopy 60
fi

# Focus the window
WID=$(get_builder_window 2>/dev/null || true)
if [[ -n "$WID" ]]; then
    focus_builder "$WID"
    maximize_window "$WID"
fi

dismiss_psychopy_dialogs 2>/dev/null || true

take_screenshot /tmp/fear_conditioning_coder_start.png 2>/dev/null || true
echo "=== fear_conditioning_coder task ready ==="
