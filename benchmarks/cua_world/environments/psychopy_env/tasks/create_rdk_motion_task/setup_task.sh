#!/bin/bash
echo "=== Setting up RDK Motion Coherence task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Create directory structure
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/data

# Create the conditions file (real experimental parameters from motion coherence literature)
# Coherence: 0.05 to 0.8
# Direction: 0.0 (right), 180.0 (left)
cat > /home/ga/PsychoPyExperiments/conditions/motion_conditions.csv << 'CSVEOF'
coherence,direction,corrAns
0.05,0.0,right
0.05,180.0,left
0.1,0.0,right
0.1,180.0,left
0.2,0.0,right
0.2,180.0,left
0.4,0.0,right
0.4,180.0,left
0.8,0.0,right
0.8,180.0,left
CSVEOF

chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing experiment file (clean state)
rm -f /home/ga/PsychoPyExperiments/motion_coherence.psyexp

# Ensure PsychoPy is running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 60
fi

# Dismiss any dialogs
sleep 5
dismiss_psychopy_dialogs

# Focus and maximize Builder
focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== RDK Motion Coherence task setup complete ==="
echo "Conditions file created at: /home/ga/PsychoPyExperiments/conditions/motion_conditions.csv"
echo "Agent should save experiment to: /home/ga/PsychoPyExperiments/motion_coherence.psyexp"