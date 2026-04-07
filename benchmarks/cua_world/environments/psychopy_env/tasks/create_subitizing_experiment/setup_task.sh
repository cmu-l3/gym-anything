#!/bin/bash
echo "=== Setting up create_subitizing_experiment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Ensure parent directory exists
mkdir -p /home/ga/PsychoPyExperiments/subitizing
chown ga:ga /home/ga/PsychoPyExperiments/subitizing

# Clean up any previous attempts to ensure a fresh start
rm -rf /home/ga/PsychoPyExperiments/subitizing/* 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Subitizing Experiment"
echo "Location: /home/ga/PsychoPyExperiments/subitizing/"