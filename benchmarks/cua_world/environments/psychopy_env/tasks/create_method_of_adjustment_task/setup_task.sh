#!/bin/bash
echo "=== Setting up create_method_of_adjustment_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure clean state
rm -f /home/ga/PsychoPyExperiments/size_matching.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/size_conditions.csv 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
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
echo "Task: Create a Method of Adjustment experiment"
echo "1. Create conditions file: /home/ga/PsychoPyExperiments/conditions/size_conditions.csv"
echo "2. Create experiment: /home/ga/PsychoPyExperiments/size_matching.psyexp"