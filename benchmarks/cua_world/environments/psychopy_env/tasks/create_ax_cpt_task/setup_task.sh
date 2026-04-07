#!/bin/bash
echo "=== Setting up create_ax_cpt_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce for integrity
record_task_start
generate_nonce

# Ensure directories exist
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing files to ensure the agent creates them
rm -f /home/ga/PsychoPyExperiments/conditions/ax_cpt_conditions.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/ax_cpt.psyexp 2>/dev/null || true

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
    sleep 5
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create AX-CPT Experiment and Conditions File"
echo "Target CSV: /home/ga/PsychoPyExperiments/conditions/ax_cpt_conditions.csv"
echo "Target Exp: /home/ga/PsychoPyExperiments/ax_cpt.psyexp"