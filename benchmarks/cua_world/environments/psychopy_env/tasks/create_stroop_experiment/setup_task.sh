#!/bin/bash
echo "=== Setting up create_stroop_experiment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Ensure conditions file exists
if [ ! -f /home/ga/PsychoPyExperiments/conditions/stroop_conditions.csv ]; then
    echo "WARNING: stroop_conditions.csv not found, copying from assets..."
    mkdir -p /home/ga/PsychoPyExperiments/conditions
    cp /workspace/assets/conditions/stroop_conditions.csv /home/ga/PsychoPyExperiments/conditions/ 2>/dev/null || true
    chown -R ga:ga /home/ga/PsychoPyExperiments/conditions
fi

# Remove any pre-existing experiment file (to prevent gaming)
rm -f /home/ga/PsychoPyExperiments/stroop_experiment.psyexp 2>/dev/null || true

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
echo "Task: Create a Stroop experiment in PsychoPy Builder"
echo "Conditions file: /home/ga/PsychoPyExperiments/conditions/stroop_conditions.csv"
echo "Save to: /home/ga/PsychoPyExperiments/stroop_experiment.psyexp"
