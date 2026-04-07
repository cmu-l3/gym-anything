#!/bin/bash
echo "=== Setting up Posner Cueing Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Ensure experiment directory exists and is clean of prior attempts
mkdir -p /home/ga/PsychoPyExperiments/data
rm -f /home/ga/PsychoPyExperiments/posner_cueing.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/posner_conditions.csv 2>/dev/null || true
chown -R ga:ga /home/ga/PsychoPyExperiments

# Record initial state
ls -la /home/ga/PsychoPyExperiments/ > /tmp/initial_file_state.txt 2>/dev/null || true

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    # Wait for PsychoPy window
    wait_for_psychopy 90
    sleep 5
    dismiss_psychopy_dialogs
fi

# Maximize Builder window
sleep 2
BUILDER_WID=$(get_builder_window)
if [ -n "$BUILDER_WID" ]; then
    maximize_window "$BUILDER_WID"
    DISPLAY=:1 wmctrl -i -a "$BUILDER_WID"
    echo "Builder window maximized: $BUILDER_WID"
else
    # Fallback to any psychopy window
    maximize_psychopy
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Posner Cueing Task setup complete ==="
echo "Task: Create posner_cueing.psyexp and posner_conditions.csv in /home/ga/PsychoPyExperiments/"