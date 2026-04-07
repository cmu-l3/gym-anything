#!/bin/bash
echo "=== Setting up dual_robot_welding_cell_commissioning task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# STEP 1: Remove any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/Documents/CoppeliaSim/exports/weld_audit.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/sequential_cycle.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/coordinated_cycle.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/commissioning_report.json 2>/dev/null || true

# STEP 2: Record task start timestamp
date +%s > /tmp/dual_robot_welding_cell_commissioning_start_ts

# STEP 3: Launch CoppeliaSim with an empty scene
# Agent must build the entire dual-robot cell from scratch
launch_coppeliasim

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

# Re-focus CoppeliaSim main window after dialog dismissal
focus_coppeliasim

# Take initial screenshot as evidence of starting state
sleep 2
take_screenshot /tmp/dual_robot_welding_cell_commissioning_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must load two UR5 robots, build the welding cell, and commission it."
