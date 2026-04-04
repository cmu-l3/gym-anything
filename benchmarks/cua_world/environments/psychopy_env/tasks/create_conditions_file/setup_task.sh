#!/bin/bash
echo "=== Setting up create_conditions_file task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/conditions/my_flanker_conditions.csv 2>/dev/null || true

# Ensure conditions directory exists
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown ga:ga /home/ga/PsychoPyExperiments/conditions

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create a flanker conditions CSV file"
echo "Save to: /home/ga/PsychoPyExperiments/conditions/my_flanker_conditions.csv"
