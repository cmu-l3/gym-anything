#!/bin/bash
set -e

echo "=== Setting up Modify Blade Count task ==="

# 1. Record task start time for anti-gaming (file freshness checks)
date +%s > /tmp/task_start_time.txt

# 2. Prepare directories
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# 3. Locate the sample project (IEA_RWT.wpa)
# Try standard locations
SAMPLE_PROJ=""
POSSIBLE_LOCATIONS=(
    "/home/ga/Documents/sample_projects/IEA_RWT.wpa"
    "/opt/qblade/sample projects/IEA_RWT.wpa"
    "/opt/qblade/sampleprojects/IEA_RWT.wpa"
)

for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        SAMPLE_PROJ="$loc"
        break
    fi
done

# Fallback: look for any .wpa file if specific one is missing
if [ -z "$SAMPLE_PROJ" ]; then
    SAMPLE_PROJ=$(find /home/ga/Documents/sample_projects -name "*.wpa" | head -n 1)
fi

if [ -z "$SAMPLE_PROJ" ]; then
    echo "ERROR: No sample project found!"
    exit 1
fi

echo "Using sample project: $SAMPLE_PROJ"

# 4. Clean up previous outputs to ensure fresh run
rm -f /home/ga/Documents/projects/two_blade_analysis.wpa
rm -f /home/ga/Documents/projects/blade_count_report.txt
rm -f /tmp/task_result.json

# 5. Launch QBlade with the project loaded
source /workspace/scripts/task_utils.sh
echo "Launching QBlade..."

# Kill existing instances
pkill -f "QBlade" || true
sleep 1

# Launch
launch_qblade "$SAMPLE_PROJ"

# 6. Wait for window and maximize
wait_for_qblade 30

# Maximize (crucial for VLM visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="