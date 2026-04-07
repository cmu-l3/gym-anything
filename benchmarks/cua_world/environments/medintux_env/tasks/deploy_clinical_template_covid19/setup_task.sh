#!/bin/bash
echo "=== Setting up deploy_clinical_template_covid19 task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Locate MedinTux DrTux directory to clean up any previous attempts
# Typical path: /home/ga/.wine/drive_c/MedinTux-2.16/Programmes/DrTux/Masques
DRTUX_MASQUES_DIR=$(find /home/ga/.wine/drive_c -type d -name "Masques" 2>/dev/null | grep "DrTux" | head -1)

if [ -n "$DRTUX_MASQUES_DIR" ]; then
    echo "Found Masques directory: $DRTUX_MASQUES_DIR"
    TARGET_DIR="$DRTUX_MASQUES_DIR/Protocoles_Urgence"
    
    # Clean up previous run artifacts
    if [ -d "$TARGET_DIR" ]; then
        echo "Removing existing target directory: $TARGET_DIR"
        rm -rf "$TARGET_DIR"
    fi
else
    echo "WARNING: Could not locate DrTux/Masques directory automatically."
    # We don't fail here, as the agent might find it, or it might be created during install if missing
fi

# 2. Ensure MedinTux Manager is running (standard start state)
launch_medintux_manager

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="