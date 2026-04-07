#!/bin/bash
echo "=== Setting up Iowa Gambling Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and nonce
record_task_start
generate_nonce

# Ensure directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/data
chown -R ga:ga /home/ga/PsychoPyExperiments

# Clean up previous attempts to ensure a fresh start
rm -f /home/ga/PsychoPyExperiments/iowa_gambling_task.psyexp 2>/dev/null
rm -f /home/ga/PsychoPyExperiments/conditions/igt_decks.csv 2>/dev/null

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 5
    dismiss_psychopy_dialogs
fi

# Focus and maximize Builder window
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Goal: Create IGT experiment and conditions file."