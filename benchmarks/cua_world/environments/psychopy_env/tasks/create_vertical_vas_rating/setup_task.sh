#!/bin/bash
echo "=== Setting up create_vertical_vas_rating task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure fresh creation
rm -f /home/ga/PsychoPyExperiments/pain_vas.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/pain_stimuli.csv 2>/dev/null || true

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

# Focus and maximize Builder window
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Vertical VAS Experiment"
echo "Save experiment to: /home/ga/PsychoPyExperiments/pain_vas.psyexp"
echo "Save conditions to: /home/ga/PsychoPyExperiments/conditions/pain_stimuli.csv"