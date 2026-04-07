#!/bin/bash
echo "=== Setting up WCST Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/data
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/wcst_task.py 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/wcst_cards.csv 2>/dev/null || true

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

# Attempt to open Coder view directly if possible, or ensure at least Builder is open
focus_builder
maximize_window "$(get_builder_window)"
sleep 1

# Try to switch to Coder view (standard workflow for coding tasks)
# Ctrl+L is often the shortcut, or we assume agent can switch.
# We'll leave it in Builder view as the "Starting State" but ensure the app is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create WCST assessment script and conditions file"
echo "Script location: /home/ga/PsychoPyExperiments/wcst_task.py"
echo "Conditions file: /home/ga/PsychoPyExperiments/conditions/wcst_cards.csv"