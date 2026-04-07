#!/bin/bash
echo "=== Setting up create_retrocue_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure clean state
rm -rf /home/ga/PsychoPyExperiments/retrocue 2>/dev/null || true
mkdir -p /home/ga/PsychoPyExperiments/retrocue
chown ga:ga /home/ga/PsychoPyExperiments/retrocue

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
echo "Task: Create Retro-Cue Visual Memory Task"
echo "Working Directory: /home/ga/PsychoPyExperiments/retrocue/"