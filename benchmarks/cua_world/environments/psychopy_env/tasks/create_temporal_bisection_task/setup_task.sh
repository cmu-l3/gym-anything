#!/bin/bash
echo "=== Setting up Temporal Bisection Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure clean state
rm -f /home/ga/PsychoPyExperiments/temporal_bisection.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/anchors.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/probes.csv 2>/dev/null || true

# Ensure PsychoPy is running
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
echo "Task: Create Temporal Bisection Task (Demo -> Training -> Testing)"
echo "Target File: /home/ga/PsychoPyExperiments/temporal_bisection.psyexp"