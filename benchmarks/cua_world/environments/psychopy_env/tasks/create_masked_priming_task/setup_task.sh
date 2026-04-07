#!/bin/bash
echo "=== Setting up Masked Priming Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Create directory structure but ensure it's empty of target files
mkdir -p /home/ga/PsychoPyExperiments/masked_priming
rm -f /home/ga/PsychoPyExperiments/masked_priming/masked_priming.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/masked_priming/stimuli.csv 2>/dev/null || true
chown -R ga:ga /home/ga/PsychoPyExperiments

# Start PsychoPy Builder if not running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

# Ensure window is visible/maximized
focus_builder
maximize_window "$(get_builder_window)"

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="