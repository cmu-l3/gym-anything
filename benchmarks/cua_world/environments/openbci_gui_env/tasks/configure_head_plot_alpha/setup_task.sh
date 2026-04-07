#!/bin/bash
set -e
echo "=== Setting up Configure Head Plot Alpha Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure EEG Recording Exists
# ============================================================
REC_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$REC_DIR"

TARGET_FILE="$REC_DIR/OpenBCI-EEG-S001-EyesOpen.txt"

# Locations to look for source data (based on install scripts)
SOURCES=(
    "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
    "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt"
    "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
)

if [ ! -f "$TARGET_FILE" ]; then
    echo "Target recording not found, attempting to copy..."
    for src in "${SOURCES[@]}"; do
        if [ -f "$src" ]; then
            echo "Copying from $src"
            cp "$src" "$TARGET_FILE"
            break
        fi
    done
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "ERROR: Could not find EEG recording file!"
    # Create a dummy file if real data is missing to prevent total blocking,
    # though the task will likely fail verification of data content.
    echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
    echo "Sample Rate = 250" >> "$TARGET_FILE"
fi

# Set permissions
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# ============================================================
# 2. Clean Up Previous Artifacts
# ============================================================
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/alpha_topography.png"

# ============================================================
# 3. Launch Application
# ============================================================
# Kill any existing instances
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

echo "Launching OpenBCI GUI..."
# Use the utility function if available, otherwise manual launch
if command -v launch_openbci >/dev/null; then
    launch_openbci
else
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"
    
    # Wait loop
    for i in {1..45}; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci"; then
            echo "Window found."
            break
        fi
        sleep 1
    done
fi

# Maximize window
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Capture initial state
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="