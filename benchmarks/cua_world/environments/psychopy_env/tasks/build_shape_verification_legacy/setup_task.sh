#!/bin/bash
set -e
echo "=== Setting up build_shape_verification_legacy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
record_task_start
generate_nonce

# Create directory structure
EXP_DIR="/home/ga/PsychoPyExperiments"
STIM_DIR="$EXP_DIR/stimuli"
mkdir -p "$STIM_DIR"

# Generate simple shape stimuli using ImageMagick
echo "Generating stimuli..."
# Circle (Blue)
convert -size 400x400 xc:white -fill blue -stroke none -draw "circle 200,200 200,350" "$STIM_DIR/circle.png"
# Square (Red)
convert -size 400x400 xc:white -fill red -stroke none -draw "rectangle 50,50 350,350" "$STIM_DIR/square.png"
# Triangle (Green)
convert -size 400x400 xc:white -fill green -stroke none -draw "polygon 200,50 350,350 50,350" "$STIM_DIR/triangle.png"

# Create the "Legacy" CSV with broken Windows paths
CSV_FILE="$EXP_DIR/legacy_conditions.csv"
cat > "$CSV_FILE" << 'EOF'
orig_path,shape_name,match_text,condition,corr_key
C:\Users\LabUser\Documents\Exp2022\Stimuli\circle.png,circle,CIRCLE,match,y
C:\Users\LabUser\Documents\Exp2022\Stimuli\square.png,square,SQUARE,match,y
C:\Users\LabUser\Documents\Exp2022\Stimuli\triangle.png,triangle,TRIANGLE,match,y
C:\Users\LabUser\Documents\Exp2022\Stimuli\circle.png,circle,SQUARE,mismatch,n
C:\Users\LabUser\Documents\Exp2022\Stimuli\square.png,square,TRIANGLE,mismatch,n
C:\Users\LabUser\Documents\Exp2022\Stimuli\triangle.png,triangle,CIRCLE,mismatch,n
EOF

# Set permissions
chown -R ga:ga "$EXP_DIR"

# Ensure PsychoPy is running
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
echo "Task: Build Shape Verification Task from Legacy Data"
echo "Legacy Data: $CSV_FILE"
echo "Stimuli: $STIM_DIR"