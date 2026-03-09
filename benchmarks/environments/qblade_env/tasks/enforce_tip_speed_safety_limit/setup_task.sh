#!/bin/bash
set -e
echo "=== Setting up enforce_tip_speed_safety_limit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/projects
rm -f /home/ga/Documents/projects/tip_limited_sim.wpa
rm -f /home/ga/Documents/tip_speed_report.txt

# Locate the sample project IEA_RWT.wpa
SAMPLE_PROJECT=""
# Check standard sample locations
POSSIBLE_LOCATIONS=(
    "/home/ga/Documents/sample_projects/IEA_RWT.wpa"
    "/home/ga/Documents/sample_projects/NREL_5MW.wpa" 
    "/opt/qblade/sample_projects/IEA_RWT.wpa"
)

for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        SAMPLE_PROJECT="$loc"
        break
    fi
done

# If specific IEA_RWT not found, try any .wpa in sample folder
if [ -z "$SAMPLE_PROJECT" ]; then
    SAMPLE_PROJECT=$(find /home/ga/Documents/sample_projects -name "*.wpa" | head -n 1)
fi

if [ -z "$SAMPLE_PROJECT" ]; then
    echo "ERROR: No sample project found to load."
    # Create a dummy one or fail? 
    # Attempting to copy from backup location if environment setup failed
    cp /workspace/data/samples/IEA_RWT.wpa /home/ga/Documents/sample_projects/ 2>/dev/null || true
    SAMPLE_PROJECT="/home/ga/Documents/sample_projects/IEA_RWT.wpa"
fi

echo "Selected sample project: $SAMPLE_PROJECT"

# Launch QBlade with the project loaded
echo "Launching QBlade..."
launch_qblade "$SAMPLE_PROJECT"

# Wait for QBlade to appear
wait_for_qblade 60

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="