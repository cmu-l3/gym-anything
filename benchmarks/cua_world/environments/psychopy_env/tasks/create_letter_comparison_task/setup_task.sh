#!/bin/bash
echo "=== Setting up Letter Comparison Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Ensure target directory exists and is empty/clean
TARGET_DIR="/home/ga/PsychoPyExperiments/letter_comparison"
rm -rf "$TARGET_DIR" 2>/dev/null || true
mkdir -p "$TARGET_DIR"
chown ga:ga "$TARGET_DIR"

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Ensure Builder is focused and maximized
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Letter Comparison Task (60s limit)"
echo "Target Directory: $TARGET_DIR"