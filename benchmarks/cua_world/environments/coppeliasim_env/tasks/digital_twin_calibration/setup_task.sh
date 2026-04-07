#!/bin/bash
echo "=== Setting up digital_twin_calibration task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/kinematic_survey.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/dynamic_excitation.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/identified_parameters.json 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/validation_results.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/characterization_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/digital_twin_calibration_start_ts

# STEP 3: Launch CoppeliaSim with the movementViaRemoteApi scene
# This scene has ZMQ remote API server running on port 23000
SCENE_FILE=$(find /opt/CoppeliaSim/scenes -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
if [ -z "$SCENE_FILE" ]; then
    SCENE_FILE=$(find /opt/CoppeliaSim -name "movementViaRemoteApi.ttt" 2>/dev/null | head -1)
fi

if [ -n "$SCENE_FILE" ]; then
    echo "Found scene: $SCENE_FILE"
    launch_coppeliasim "$SCENE_FILE"
else
    echo "WARNING: movementViaRemoteApi.ttt not found, launching empty scene"
    launch_coppeliasim
fi

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss standard startup dialogs (Welcome / language selection)
sleep 2
dismiss_dialogs

# Extra: dismiss CoppeliaSim registration/license dialogs
# These are known to block the ZMQ API and were not caught by the standard dismiss_dialogs
sleep 1
for dialog_title in "Registration" "Key is not valid" "License" "registration"; do
    DLG_WID=$(DISPLAY=:1 xdotool search --name "$dialog_title" 2>/dev/null | head -1)
    if [ -n "$DLG_WID" ]; then
        echo "Dismissing '$dialog_title' dialog..."
        DISPLAY=:1 xdotool windowactivate "$DLG_WID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
        # If Escape didn't work, try clicking OK/Cancel
        STILL=$(DISPLAY=:1 xdotool search --name "$dialog_title" 2>/dev/null | head -1)
        if [ -n "$STILL" ]; then
            DISPLAY=:1 xdotool key Return 2>/dev/null || true
            sleep 0.5
        fi
    fi
done

# Second pass for any remaining dialogs after the first round
sleep 1
dismiss_dialogs
for dialog_title in "Registration" "Key is not valid" "License" "registration"; do
    DLG_WID=$(DISPLAY=:1 xdotool search --name "$dialog_title" 2>/dev/null | head -1)
    if [ -n "$DLG_WID" ]; then
        echo "Second pass: dismissing '$dialog_title' dialog..."
        DISPLAY=:1 xdotool windowactivate "$DLG_WID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
    fi
done

# Re-focus CoppeliaSim main window after dialog dismissal
focus_coppeliasim

# Take initial screenshot as evidence of starting state
sleep 2
take_screenshot /tmp/digital_twin_calibration_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with movementViaRemoteApi.ttt scene."
echo "Agent must load a UR5 robot, attach an end-effector, and perform characterization."
