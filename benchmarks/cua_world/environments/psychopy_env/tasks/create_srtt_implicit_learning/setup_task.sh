#!/bin/bash
echo "=== Setting up SRTT Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time and nonce for anti-gaming
record_task_start
generate_nonce

# 2. Prepare directory structure (clean state)
EXP_DIR="/home/ga/PsychoPyExperiments"
mkdir -p "$EXP_DIR/conditions"
chown -R ga:ga "$EXP_DIR"

# Remove any pre-existing target files to ensure fresh creation
rm -f "$EXP_DIR/srtt_experiment.psyexp"
rm -f "$EXP_DIR/conditions/srtt_sequence_block.csv"
rm -f "$EXP_DIR/conditions/srtt_random_block.csv"
rm -f "$EXP_DIR/conditions/srtt_blocks.csv"

# 3. Launch PsychoPy if not running
if ! is_psychopy_running; then
    echo "Starting PsychoPy..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    
    # Wait for window
    wait_for_psychopy 60
    sleep 5
fi

# 4. Prepare UI
dismiss_psychopy_dialogs
focus_builder
maximize_window "$(get_builder_window)"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="