#!/bin/bash
echo "=== Setting up create_time_to_contact_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments/ttc_task
chown ga:ga /home/ga/PsychoPyExperiments/ttc_task

# Clean up any previous attempts (to prevent gaming)
rm -f /home/ga/PsychoPyExperiments/ttc_task/ttc_task.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/ttc_task/conditions.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/ttc_task/road_bg.jpg 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Time-to-Contact Experiment"
echo "Location: /home/ga/PsychoPyExperiments/ttc_task/"