#!/bin/bash
echo "=== Setting up build_gonogo_inhibition_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Ensure parent directory exists but CLEAN the target task directory
# We want the agent to create the folder structure if possible, 
# or at least populate a clean one.
TARGET_DIR="/home/ga/PsychoPyExperiments/go_nogo_task"

if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# Ensure the parent experiments directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

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
echo "Task: Build Go/No-Go Experiment"
echo "Target Directory: $TARGET_DIR"