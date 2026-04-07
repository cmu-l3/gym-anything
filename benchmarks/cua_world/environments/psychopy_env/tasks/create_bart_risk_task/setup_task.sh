#!/bin/bash
echo "=== Setting up BART Task ==="

source /workspace/scripts/task_utils.sh

# Record start time and generate nonce
record_task_start
generate_nonce

# Create directory structure
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any existing target files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/bart_task.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/bart_config.csv 2>/dev/null || true

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Focus the Builder window
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create BART Experiment"
echo "1. Config: /home/ga/PsychoPyExperiments/conditions/bart_config.csv"
echo "2. Experiment: /home/ga/PsychoPyExperiments/bart_task.psyexp"