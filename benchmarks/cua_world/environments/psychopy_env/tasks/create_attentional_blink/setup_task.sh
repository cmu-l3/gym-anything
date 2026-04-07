#!/bin/bash
echo "=== Setting up Attentional Blink task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
record_task_start
generate_nonce

# Clean previous task artifacts to ensure fresh start
rm -f /home/ga/PsychoPyExperiments/attentional_blink.psyexp 2>/dev/null
rm -f /home/ga/PsychoPyExperiments/conditions/ab_conditions.csv 2>/dev/null

# Ensure directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/data
chown -R ga:ga /home/ga/PsychoPyExperiments

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
fi

# Give it a moment to settle
sleep 5

# Dismiss any startup dialogs (tips, etc.)
dismiss_psychopy_dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize Builder window
focus_builder
WID=$(get_builder_window)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    echo "PsychoPy Builder maximized"
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Attentional Blink Experiment"
echo "Save experiment to: /home/ga/PsychoPyExperiments/attentional_blink.psyexp"
echo "Save conditions to: /home/ga/PsychoPyExperiments/conditions/ab_conditions.csv"