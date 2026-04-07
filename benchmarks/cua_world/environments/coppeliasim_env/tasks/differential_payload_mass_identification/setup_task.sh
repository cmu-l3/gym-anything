#!/bin/bash
echo "=== Setting up differential_payload_mass_identification task ==="

source /workspace/scripts/task_utils.sh

# Create workspace output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove pre-existing output files (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/torque_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/payload_estimation.json 2>/dev/null || true

# STEP 2: Record task start timestamp for verification
date +%s > /tmp/payload_mass_identification_start_ts

# STEP 3: Launch CoppeliaSim with the default remote API messaging scene
# This scene typically contains a UR5 or similar 6-DOF robot arm.
SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" -path "*/messaging/*" 2>/dev/null | head -1)
if [ -z "$SCENE" ]; then
    SCENE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi
if [ -n "$SCENE" ] && [ -f "$SCENE" ]; then
    echo "Loading base robot scene: $SCENE"
    launch_coppeliasim "$SCENE"
else
    echo "Warning: Base scene not found, launching empty scene"
    launch_coppeliasim
fi

# Ensure visibility
focus_coppeliasim
maximize_coppeliasim

# Let UI settle and dismiss dialogs
sleep 2
dismiss_dialogs

# Take evidence screenshot of initial state
sleep 2
take_screenshot /tmp/payload_mass_identification_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim running. Agent must build the payload, measure torques, and estimate mass."