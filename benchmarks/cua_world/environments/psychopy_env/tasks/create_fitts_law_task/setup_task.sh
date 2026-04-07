#!/bin/bash
echo "=== Setting up create_fitts_law_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist (but empty them to ensure clean slate)
mkdir -p /home/ga/PsychoPyExperiments/fitts_law/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/PsychoPyExperiments/fitts_law/fitts_task.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/fitts_law/conditions/fitts_targets.csv 2>/dev/null || true

# Ensure PsychoPy is running
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
echo "Task: Create Fitts' Law Experiment"
echo "Location: /home/ga/PsychoPyExperiments/fitts_law/"