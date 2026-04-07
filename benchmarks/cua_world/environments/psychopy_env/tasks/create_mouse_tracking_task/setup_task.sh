#!/bin/bash
echo "=== Setting up create_mouse_tracking_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/mouse_tracking.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/competitors.csv 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create a mouse-tracking experiment"
echo "1. Create conditions file: competitors.csv"
echo "2. Build experiment with Start routine and continuous mouse logging"
echo "Save to: /home/ga/PsychoPyExperiments/mouse_tracking.psyexp"