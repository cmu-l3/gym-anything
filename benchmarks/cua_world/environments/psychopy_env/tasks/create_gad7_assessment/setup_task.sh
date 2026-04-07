#!/bin/bash
echo "=== Setting up GAD-7 Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Clean up any previous attempts to ensure clean state
rm -f /home/ga/PsychoPyExperiments/gad7_items.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/gad7_assessment.psyexp 2>/dev/null || true

# Launch PsychoPy Builder if not running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Ensure Builder is focused and maximized
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create GAD-7 Assessment"
echo "  1. CSV: /home/ga/PsychoPyExperiments/gad7_items.csv"
echo "  2. Exp: /home/ga/PsychoPyExperiments/gad7_assessment.psyexp"