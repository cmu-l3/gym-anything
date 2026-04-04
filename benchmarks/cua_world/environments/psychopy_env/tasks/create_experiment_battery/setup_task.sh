#!/bin/bash
echo "=== Setting up create_experiment_battery task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output file
rm -f /home/ga/PsychoPyExperiments/cognitive_battery.psyexp 2>/dev/null || true

# Ensure all three conditions files are available
for csv in stroop_conditions.csv flanker_conditions.csv simon_conditions.csv; do
    if [ ! -f "/home/ga/PsychoPyExperiments/conditions/$csv" ]; then
        cp "/workspace/assets/conditions/$csv" "/home/ga/PsychoPyExperiments/conditions/$csv"
        chown ga:ga "/home/ga/PsychoPyExperiments/conditions/$csv"
    fi
done

# Record baseline: which conditions files exist
echo "stroop_conditions.csv flanker_conditions.csv simon_conditions.csv" > /tmp/initial_conditions_files
ls /home/ga/PsychoPyExperiments/conditions/*.csv 2>/dev/null | wc -l > /tmp/initial_conditions_count

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
echo "Task: Create a cognitive experiment battery combining Stroop, Flanker, and Simon"
echo "Conditions files available in /home/ga/PsychoPyExperiments/conditions/"
echo "Save battery as: /home/ga/PsychoPyExperiments/cognitive_battery.psyexp"
