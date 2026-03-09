#!/usr/bin/env bash
# Setup for ace3_episodic_memory task.
# Removes any pre-existing output files so the agent must create them fresh,
# ensures PsychoPy is running and Builder is open.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /workspace/scripts/task_utils.sh

record_task_start

# Remove any pre-existing output files so agent must create them fresh
rm -f /home/ga/PsychoPyExperiments/ace3_episodic_memory.psyexp
rm -f /home/ga/PsychoPyExperiments/conditions/ace3_recognition.csv

# Ensure output directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    launch_psychopy_builder
    wait_for_psychopy 60
fi

# Focus the Builder window
WID=$(get_builder_window 2>/dev/null || true)
if [[ -n "$WID" ]]; then
    focus_builder "$WID"
    maximize_window "$WID"
fi

dismiss_psychopy_dialogs 2>/dev/null || true

take_screenshot /tmp/ace3_episodic_memory_start.png 2>/dev/null || true
echo "=== ace3_episodic_memory task ready ==="
