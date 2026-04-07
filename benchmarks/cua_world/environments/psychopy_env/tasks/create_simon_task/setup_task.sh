#!/bin/bash
echo "=== Setting up Simon Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure parent directory exists but clean the specific task directory
mkdir -p /home/ga/PsychoPyExperiments
rm -rf /home/ga/PsychoPyExperiments/simon_task
mkdir -p /home/ga/PsychoPyExperiments/simon_task
chown -R ga:ga /home/ga/PsychoPyExperiments

# Ensure PsychoPy is running
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
echo "Task: Create Simon Effect Task"
echo "Location: /home/ga/PsychoPyExperiments/simon_task/"