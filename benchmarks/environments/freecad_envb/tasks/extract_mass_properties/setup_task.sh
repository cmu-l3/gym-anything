#!/bin/bash
echo "=== Setting up extract_mass_properties task ==="

# Kill any running FreeCAD instances
pkill -f freecad 2>/dev/null || true
sleep 2

# Define paths
DOCS_DIR="/home/ga/Documents/FreeCAD"
MODEL_FILE="$DOCS_DIR/T8_housing_bracket.FCStd"
REPORT_FILE="$DOCS_DIR/mass_report.json"
SOURCE_FILE="/opt/freecad_samples/T8_housing_bracket.FCStd"

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown -R ga:ga "$DOCS_DIR"

# Clean up previous results
rm -f "$REPORT_FILE"

# Ensure the T8 housing bracket model is present
if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$MODEL_FILE"
    echo "Restored T8_housing_bracket.FCStd from samples."
else
    echo "ERROR: Source file $SOURCE_FILE not found."
    # Fallback for testing without mounted data: create a simple dummy file if needed
    # but strictly we should fail if data is missing.
    exit 1
fi

# Set permissions
chown ga:ga "$MODEL_FILE"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch FreeCAD with the file loaded
echo "Launching FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad '$MODEL_FILE' > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window
echo "Waiting for FreeCAD to start..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD"; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Ensure the model is visible (Fit All)
sleep 5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key v f 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="