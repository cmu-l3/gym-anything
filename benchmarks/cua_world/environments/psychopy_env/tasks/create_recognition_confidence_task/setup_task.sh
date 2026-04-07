#!/bin/bash
echo "=== Setting up create_recognition_confidence_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure a clean start
rm -f /home/ga/PsychoPyExperiments/recognition_confidence.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/study_list.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/test_list.csv 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Recognition Memory Task with Conditional Logic"
echo "Save experiment to: /home/ga/PsychoPyExperiments/recognition_confidence.psyexp"
echo "Save conditions to: /home/ga/PsychoPyExperiments/conditions/"