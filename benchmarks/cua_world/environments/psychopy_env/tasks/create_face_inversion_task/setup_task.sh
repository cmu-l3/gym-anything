#!/bin/bash
echo "=== Setting up Face Inversion Task ==="

source /workspace/scripts/task_utils.sh

# Record start time and nonce
record_task_start
generate_nonce

# Create directory structure
EXP_DIR="/home/ga/PsychoPyExperiments"
STIM_DIR="$EXP_DIR/stimuli"
COND_DIR="$EXP_DIR/conditions"

mkdir -p "$STIM_DIR"
mkdir -p "$COND_DIR"

# Clean previous outputs to ensure fresh creation
rm -f "$EXP_DIR/face_inversion.psyexp" 2>/dev/null || true
rm -f "$COND_DIR/inversion_conditions.csv" 2>/dev/null || true

# Generate stimulus images using ImageMagick (simulating real stimuli)
echo "Generating stimuli..."

# Face 1
convert -size 400x400 xc:white -fill black -draw "circle 200,200 200,50" \
    -fill white -draw "circle 150,150 150,130" -draw "circle 250,150 250,130" \
    -fill black -draw "rectangle 150,250 250,260" \
    -pointsize 30 -draw "text 160,350 'FACE 1'" \
    "$STIM_DIR/face1.png"

# Face 2
convert -size 400x400 xc:lightblue -fill black -draw "circle 200,200 200,50" \
    -fill white -draw "circle 150,150 150,130" -draw "circle 250,150 250,130" \
    -fill black -draw "rectangle 150,250 250,260" \
    -pointsize 30 -draw "text 160,350 'FACE 2'" \
    "$STIM_DIR/face2.png"

# House 1
convert -size 400x400 xc:white -fill none -stroke black -strokewidth 5 \
    -draw "rectangle 100,200 300,350" -draw "polyline 100,200 200,100 300,200" \
    -fill black -stroke none -draw "text 150,380 'HOUSE 1'" \
    "$STIM_DIR/house1.png"

# House 2
convert -size 400x400 xc:lightyellow -fill none -stroke black -strokewidth 5 \
    -draw "rectangle 100,200 300,350" -draw "polyline 100,200 200,100 300,200" \
    -fill black -stroke none -draw "text 150,380 'HOUSE 2'" \
    "$STIM_DIR/house2.png"

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
echo "Stimuli generated in: $STIM_DIR"
echo "Save experiment to: $EXP_DIR/face_inversion.psyexp"