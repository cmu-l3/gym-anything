#!/bin/bash
echo "=== Setting up p300_auditory_oddball task ==="

source /workspace/scripts/task_utils.sh

record_task_start
generate_nonce

mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output files
rm -f /home/ga/PsychoPyExperiments/p300_oddball.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/p300_conditions.csv 2>/dev/null || true

# Ensure PsychoPy is running and in Builder mode
if ! is_psychopy_running; then
    echo "Launching PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 30
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== P300 auditory oddball task setup complete ==="
echo "Target psyexp: /home/ga/PsychoPyExperiments/p300_oddball.psyexp"
echo "Target conditions: /home/ga/PsychoPyExperiments/conditions/p300_conditions.csv"
echo "Required: 300 rows (240 standard 1000Hz + 60 deviant 2000Hz)"
