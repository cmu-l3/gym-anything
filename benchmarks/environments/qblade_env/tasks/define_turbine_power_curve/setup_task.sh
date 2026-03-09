#!/bin/bash
echo "=== Setting up Define Turbine Power Curve Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous runs
rm -f /home/ga/Documents/projects/NREL5MW_turbine_sim.wpa
rm -f /home/ga/Documents/projects/power_curve_report.txt
rm -f /tmp/task_start_time.txt
mkdir -p /home/ga/Documents/projects

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Locate the NREL 5MW Sample Project
# QBlade v0.96 often comes with "NREL 5MW Reference Turbine.wpa"
SAMPLE_PROJECT=""
SEARCH_DIRS=(
    "/home/ga/Documents/sample_projects"
    "/opt/qblade/sample projects"
    "/opt/qblade/sampleprojects"
)

echo "Searching for NREL 5MW sample project..."
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        FOUND=$(find "$dir" -name "*NREL*5MW*.wpa" | head -n 1)
        if [ -n "$FOUND" ]; then
            SAMPLE_PROJECT="$FOUND"
            echo "Found sample project: $SAMPLE_PROJECT"
            break
        fi
    fi
done

# Fallback: if specific NREL 5MW not found, find ANY valid project with polars (largest wpa)
if [ -z "$SAMPLE_PROJECT" ]; then
    echo "WARNING: NREL 5MW specific file not found. Using largest available sample project."
    SAMPLE_PROJECT=$(find /home/ga/Documents/sample_projects -name "*.wpa" -type f -printf "%s %p\n" | sort -nr | head -n 1 | awk '{print $2}')
fi

if [ -z "$SAMPLE_PROJECT" ]; then
    echo "ERROR: No sample projects found. Task cannot proceed."
    exit 1
fi

# 4. Launch QBlade with the project loaded
echo "Launching QBlade with project: $SAMPLE_PROJECT"

# Kill existing
pkill -f "QBlade" 2>/dev/null || true
sleep 2

# Launch
launch_qblade "$SAMPLE_PROJECT"

# 5. Wait for window and maximize
wait_for_qblade 60

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="