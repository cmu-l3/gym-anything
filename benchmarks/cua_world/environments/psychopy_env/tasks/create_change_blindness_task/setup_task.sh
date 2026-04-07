#!/bin/bash
echo "=== Setting up Create Change Blindness Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Clean up any previous attempts to ensure a fresh start
EXP_DIR="/home/ga/PsychoPyExperiments"
rm -f "$EXP_DIR/change_blindness.psyexp" 2>/dev/null || true
rm -f "$EXP_DIR/conditions.csv" 2>/dev/null || true
rm -rf "$EXP_DIR/stimuli" 2>/dev/null || true

# Ensure base directory exists
mkdir -p "$EXP_DIR"
chown ga:ga "$EXP_DIR"

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Change Blindness Flicker Experiment"
echo "Location: /home/ga/PsychoPyExperiments/"