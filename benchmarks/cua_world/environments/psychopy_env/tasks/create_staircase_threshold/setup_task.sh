#!/bin/bash
echo "=== Setting up create_staircase_threshold task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing experiment file to ensure clean state
rm -f /home/ga/PsychoPyExperiments/contrast_threshold_staircase.psyexp 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Ensure Builder is the focused window
focus_builder
maximize_window "$(get_builder_window)"
sleep 1

# Dismiss any lingering dialogs (like "Tips" or "Updates")
dismiss_psychopy_dialogs

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create a contrast threshold staircase experiment"
echo "Save to: /home/ga/PsychoPyExperiments/contrast_threshold_staircase.psyexp"