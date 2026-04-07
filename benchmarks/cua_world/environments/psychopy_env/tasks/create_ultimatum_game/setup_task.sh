#!/bin/bash
echo "=== Setting up create_ultimatum_game task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification checks)
record_task_start
generate_nonce

# Ensure target directory exists and is clean
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

# Clean up previous attempts to ensure we verify fresh work
rm -f /home/ga/PsychoPyExperiments/ultimatum_game.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/ug_conditions.csv 2>/dev/null || true

# Ensure PsychoPy is running and focused
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Focus and maximize Builder window
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Ultimatum Game experiment and conditions file."
echo "Locations:"
echo "  - Experiment: /home/ga/PsychoPyExperiments/ultimatum_game.psyexp"
echo "  - Conditions: /home/ga/PsychoPyExperiments/ug_conditions.csv"