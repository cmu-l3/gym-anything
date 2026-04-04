#!/bin/bash
echo "=== Setting up Isometric Game Asset Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
DEMO_DIR="/home/ga/BlenderDemos"
PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Source File (BMW Benchmark)
# We look for the standard BMW27.blend. If not found, we download it.
SOURCE_BLEND="$DEMO_DIR/BMW27.blend"

if [ ! -f "$SOURCE_BLEND" ]; then
    echo "Downloading BMW benchmark scene..."
    mkdir -p "$DEMO_DIR"
    wget -q -O "/tmp/BMW27.zip" "https://download.blender.org/demo/test/BMW27.blend.zip"
    unzip -q -o "/tmp/BMW27.zip" -d "$DEMO_DIR"
    # Handle potential subfolder structure from zip
    if [ -f "$DEMO_DIR/BMW27/BMW27.blend" ]; then
        mv "$DEMO_DIR/BMW27/BMW27.blend" "$DEMO_DIR/BMW27.blend"
    fi
    rm -f "/tmp/BMW27.zip"
fi

# Create a fresh working copy for the task
# We name it 'isometric_start.blend' so the agent has a clean file
WORKING_BLEND="$PROJECT_DIR/isometric_start.blend"
if [ -f "$SOURCE_BLEND" ]; then
    cp "$SOURCE_BLEND" "$WORKING_BLEND"
    chown ga:ga "$WORKING_BLEND"
else
    echo "ERROR: Could not setup source file."
    exit 1
fi

# Clean previous outputs
rm -f "$PROJECT_DIR/iso_icon.png"
rm -f "$PROJECT_DIR/iso_setup.blend"

# Launch Blender with the working file
echo "Launching Blender..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORKING_BLEND' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
            echo "Blender window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="