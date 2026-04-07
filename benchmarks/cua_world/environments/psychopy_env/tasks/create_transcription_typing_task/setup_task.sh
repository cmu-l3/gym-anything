#!/bin/bash
echo "=== Setting up Create Transcription Typing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Ensure target directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output files to prevent gaming
rm -f /home/ga/PsychoPyExperiments/conditions/phrases.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/transcription_task.psyexp 2>/dev/null || true

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
echo "Task: Create transcription typing experiment"
echo "1. Create CSV at: /home/ga/PsychoPyExperiments/conditions/phrases.csv"
echo "2. Create Experiment at: /home/ga/PsychoPyExperiments/transcription_task.psyexp"