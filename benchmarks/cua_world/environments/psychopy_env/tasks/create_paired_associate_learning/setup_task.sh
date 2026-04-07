#!/bin/bash
echo "=== Setting up create_paired_associate_learning task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Create and own the directory to ensure agent can write there
mkdir -p /home/ga/PsychoPyExperiments/paired_associates
chown ga:ga /home/ga/PsychoPyExperiments/paired_associates

# Clean up any previous files to ensure a fresh start
rm -f /home/ga/PsychoPyExperiments/paired_associates/paired_associates.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/paired_associates/conditions.csv 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 5
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Paired-Associate Learning Experiment"
echo "Target Directory: /home/ga/PsychoPyExperiments/paired_associates/"