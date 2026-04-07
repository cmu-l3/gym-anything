#!/bin/bash
echo "=== Setting up create_pitch_discrimination task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure directory structure exists
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/pitch_discrimination.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/pitch_conditions.csv 2>/dev/null || true

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
echo "Task: Create 2IFC Pitch Discrimination Experiment"
echo "Save Experiment to: /home/ga/PsychoPyExperiments/pitch_discrimination.psyexp"
echo "Save Conditions to: /home/ga/PsychoPyExperiments/conditions/pitch_conditions.csv"