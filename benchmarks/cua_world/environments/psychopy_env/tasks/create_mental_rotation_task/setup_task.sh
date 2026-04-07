#!/bin/bash
echo "=== Setting up create_mental_rotation_task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# Create directory structure
EXP_DIR="/home/ga/PsychoPyExperiments/mental_rotation"
mkdir -p "$EXP_DIR"
chown ga:ga "$EXP_DIR"

# Clean up any previous attempts
rm -f "$EXP_DIR/mental_rotation.psyexp" 2>/dev/null || true

# Create conditions.csv
# Cooper & Shepard (1973) style: 5 letters x 6 angles x 2 types (normal/mirror)
cat > "$EXP_DIR/conditions.csv" << 'EOF'
letter,angle,matchType,corrAns
R,0,same,j
R,60,same,j
R,120,same,j
R,180,same,j
R,240,same,j
R,300,same,j
R,0,mirror,f
R,60,mirror,f
R,120,mirror,f
R,180,mirror,f
R,240,mirror,f
R,300,mirror,f
G,0,same,j
G,60,same,j
G,120,same,j
G,180,same,j
G,240,same,j
G,300,same,j
G,0,mirror,f
G,60,mirror,f
G,120,mirror,f
G,180,mirror,f
G,240,mirror,f
G,300,mirror,f
F,0,same,j
F,60,same,j
F,120,same,j
F,180,same,j
F,240,same,j
F,300,same,j
F,0,mirror,f
F,60,mirror,f
F,120,mirror,f
F,180,mirror,f
F,240,mirror,f
F,300,mirror,f
J,0,same,j
J,60,same,j
J,120,same,j
J,180,same,j
J,240,same,j
J,300,same,j
J,0,mirror,f
J,60,mirror,f
J,120,mirror,f
J,180,mirror,f
J,240,mirror,f
J,300,mirror,f
P,0,same,j
P,60,same,j
P,120,same,j
P,180,same,j
P,240,same,j
P,300,same,j
P,0,mirror,f
P,60,mirror,f
P,120,mirror,f
P,180,mirror,f
P,240,mirror,f
P,300,mirror,f
EOF

# Verify CSV creation
if [ -f "$EXP_DIR/conditions.csv" ]; then
    echo "Conditions file created: $EXP_DIR/conditions.csv"
    chown ga:ga "$EXP_DIR/conditions.csv"
    # Store checksum to detect tampering (though modification is allowed if valid)
    md5sum "$EXP_DIR/conditions.csv" > /tmp/conditions_checksum.txt
else
    echo "ERROR: Failed to create conditions file"
    exit 1
fi

# Ensure PsychoPy is running and focused on Builder
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 5
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create Mental Rotation Experiment"
echo "Conditions file: $EXP_DIR/conditions.csv"
echo "Save path: $EXP_DIR/mental_rotation.psyexp"