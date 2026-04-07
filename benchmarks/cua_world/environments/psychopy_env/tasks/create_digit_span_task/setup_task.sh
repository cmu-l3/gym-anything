#!/bin/bash
echo "=== Setting up digit span task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Clean any previous attempt to ensure a fresh start
rm -rf /home/ga/PsychoPyExperiments/digit_span 2>/dev/null || true

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    sleep 5
fi

# Wait for PsychoPy window
if wait_for_psychopy 60; then
    echo "PsychoPy is ready"
else
    echo "WARNING: PsychoPy window not detected"
fi

# Dismiss any dialogs
sleep 3
dismiss_psychopy_dialogs
sleep 2

# Maximize Builder window
focus_builder
maximize_psychopy

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Digit span task setup complete ==="