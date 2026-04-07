#!/bin/bash
echo "=== Setting up Eyewitness Lineup Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce
record_task_start
generate_nonce

# 1. Prepare Asset Directory
ASSET_DIR="/home/ga/Documents/TaskData/faces"
mkdir -p "$ASSET_DIR"
chown ga:ga "$ASSET_DIR"

# 2. Generate Face Assets (using ImageMagick to create distinct placeholders)
# We create 1 suspect and 5 foils
echo "Generating face assets..."

# Suspect (Reddish tint)
convert -size 200x250 xc:mistyrose -gravity center -pointsize 24 -annotate 0 "Suspect" \
    -bordercolor red -border 5 "$ASSET_DIR/suspect.jpg"

# Foils (Grayish/Blue tints)
for i in {1..5}; do
    convert -size 200x250 xc:aliceblue -gravity center -pointsize 24 -annotate 0 "Foil $i" \
        -bordercolor gray -border 2 "$ASSET_DIR/foil_$i.jpg"
done

chown -R ga:ga "/home/ga/Documents/TaskData"

# 3. Create Target Directory
EXPERIMENT_DIR="/home/ga/PsychoPyExperiments/eyewitness"
mkdir -p "$EXPERIMENT_DIR"
chown ga:ga "$EXPERIMENT_DIR"

# Remove any existing output file to ensure a clean start
rm -f "$EXPERIMENT_DIR/lineup_task.psyexp" 2>/dev/null || true

# 4. Launch PsychoPy
if ! is_psychopy_running; then
    echo "PsychoPy not running, launching..."
    su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
    wait_for_psychopy 45
    sleep 3
    dismiss_psychopy_dialogs
fi

focus_builder
maximize_window "$(get_builder_window)"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Assets created in: $ASSET_DIR"
echo "  - suspect.jpg"
echo "  - foil_1.jpg ... foil_5.jpg"
echo "Task: Create lineup_task.psyexp with a 2x3 grid of these faces."