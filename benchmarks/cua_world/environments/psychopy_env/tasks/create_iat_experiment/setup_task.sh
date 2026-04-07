#!/bin/bash
echo "=== Setting up Create IAT Experiment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Clean up any previous attempts to ensure a fresh start
rm -rf /home/ga/PsychoPyExperiments/IAT 2>/dev/null || true

# Ensure parent directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Flower-Insect IAT"
echo "Location: /home/ga/PsychoPyExperiments/IAT/"