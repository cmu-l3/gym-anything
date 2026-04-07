#!/bin/bash
echo "=== Setting up create_pvt_vigilance_task task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
record_task_start
generate_nonce

# Ensure directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove files if they already exist (start fresh)
rm -f /home/ga/PsychoPyExperiments/pvt_task.psyexp
rm -f /home/ga/PsychoPyExperiments/conditions/pvt_trials.csv

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
echo "Task: Create PVT Experiment"
echo "1. Conditions: 5 trials (2.0, 5.0, 3.5, 8.0, 4.0)"
echo "2. Dynamic counter: Updates every frame (red)"
echo "3. Logic: Detect False Starts (< 150ms)"