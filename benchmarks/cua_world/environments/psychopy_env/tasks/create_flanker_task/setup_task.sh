#!/bin/bash
echo "=== Setting up create_flanker_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/flanker_task.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/flanker_conditions.csv 2>/dev/null || true

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
echo "Task: Create Eriksen Flanker Task"
echo "1. CSV: /home/ga/PsychoPyExperiments/conditions/flanker_conditions.csv"
echo "2. Exp: /home/ga/PsychoPyExperiments/flanker_task.psyexp"