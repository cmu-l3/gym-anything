#!/bin/bash
echo "=== Setting up configure_calibrated_monitor task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Cleanup: Remove the specific monitor if it exists to ensure fresh start
# Monitors are stored in ~/.psychopy3/monitors/
rm -f /home/ga/.psychopy3/monitors/LabView.json 2>/dev/null || true
rm -f /home/ga/.psychopy3/monitors/LabView.calib 2>/dev/null || true

# Cleanup: Remove target experiment file
rm -f /home/ga/PsychoPyExperiments/visual_angle_test.psyexp 2>/dev/null || true

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
echo "Task: Configure monitor 'LabView' and create experiment 'visual_angle_test.psyexp'"