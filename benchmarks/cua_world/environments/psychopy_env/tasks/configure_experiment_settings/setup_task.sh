#!/bin/bash
echo "=== Setting up configure_experiment_settings task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

# Ensure target directory exists
mkdir -p /home/ga/PsychoPyExperiments
chown ga:ga /home/ga/PsychoPyExperiments

rm -f /home/ga/PsychoPyExperiments/attention_study.psyexp 2>/dev/null || true

if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Configure experiment settings"
echo "Save to: /home/ga/PsychoPyExperiments/attention_study.psyexp"
