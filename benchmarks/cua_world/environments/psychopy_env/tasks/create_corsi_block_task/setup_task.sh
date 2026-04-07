#!/bin/bash
echo "=== Setting up Corsi Block-Tapping Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Ensure directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/data
chown -R ga:ga /home/ga/PsychoPyExperiments

# Clean up any previous attempts (anti-gaming)
rm -f /home/ga/PsychoPyExperiments/corsi_task.py
rm -f /home/ga/PsychoPyExperiments/conditions/corsi_sequences.csv
rm -f /home/ga/PsychoPyExperiments/data/corsi_*.csv

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 3
    dismiss_psychopy_dialogs
fi

# Try to open Coder view specifically, as this is a coding task
echo "Attempting to switch to Coder view..."
CODER_WIN="$(get_coder_window)"
if [ -z "$CODER_WIN" ]; then
    # If Coder not open, try to open it from Builder
    focus_builder
    # Ctrl+L is often the shortcut for Coder view
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 3
    # Fallback: Alt+V -> C (View -> Coder)
    if [ -z "$(get_coder_window)" ]; then
        DISPLAY=:1 xdotool key alt+v 2>/dev/null
        sleep 0.5
        DISPLAY=:1 xdotool key c 2>/dev/null
        sleep 3
    fi
fi

CODER_WIN="$(get_coder_window)"
if [ -n "$CODER_WIN" ]; then
    maximize_window "$CODER_WIN"
    focus_window "$CODER_WIN"
else
    # Fallback to maximizing whatever we have
    maximize_psychopy
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Corsi Block-Tapping Task setup complete ==="