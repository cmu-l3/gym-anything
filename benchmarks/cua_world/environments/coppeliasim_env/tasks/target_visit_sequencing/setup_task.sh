#!/bin/bash
echo "=== Setting up target_visit_sequencing task ==="

source /workspace/scripts/task_utils.sh

# Create output directories with correct ownership
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/visit_sequences.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/sequencing_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/target_visit_sequencing_start_ts

# STEP 3: Launch CoppeliaSim with the movementViaRemoteApi scene
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "movementViaRemoteApi scene not found, launching empty"
    launch_coppeliasim
fi

# Focus, maximize, and prepare UI
focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/target_visit_sequencing_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with the movementViaRemoteApi scene."
echo "Agent must generate targets, test sequences, and export results."