#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up ADF Unit Root Test task ==="

# 1. Establish Time Anchors for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean Environment
# Kill running instances to ensure clean start
kill_gretl
# Remove previous outputs
rm -f /home/ga/Documents/gretl_output/adf_results.txt
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# 3. Ensure Dataset Integrity
# Check if usa.gdt exists, restore if missing
if [ ! -f /home/ga/Documents/gretl_data/usa.gdt ]; then
    echo "Restoring usa.gdt..."
    restore_dataset "usa.gdt" "/home/ga/Documents/gretl_data/usa.gdt"
fi

# 4. Generate Ground Truth (Hidden from Agent)
# We use gretlcli to run the exact tests and save the "correct" answer
echo "Computing ground truth statistics..."
GT_SCRIPT="/tmp/calc_ground_truth.inp"
cat > "$GT_SCRIPT" << 'EOF'
open "/home/ga/Documents/gretl_data/usa.gdt" --quiet
outfile "/tmp/ground_truth_output.txt"
    # 1. GDP Levels (Constant + Trend, 4 lags)
    adf 4 gdp --c --ct --verbose
    
    # 2. GDP Difference (Constant, 4 lags)
    # Note: 'diff(gdp)' creates the series if it doesn't exist implicitly in adf command
    adf 4 diff(gdp) --c --verbose
    
    # 3. Inflation Levels (Constant, 4 lags)
    adf 4 inf --c --verbose
end outfile
EOF

# execute as ga user to ensure permission consistency, but to hidden tmp file
su - ga -c "gretlcli -b $GT_SCRIPT" > /dev/null 2>&1 || echo "Warning: Ground truth calculation generated errors"

# verify ground truth was created
if [ -f "/tmp/ground_truth_output.txt" ]; then
    echo "Ground truth calculated successfully."
    chmod 644 /tmp/ground_truth_output.txt
else
    echo "ERROR: Failed to calculate ground truth."
fi

# 5. Launch Application
# Launch Gretl with the dataset pre-loaded
launch_gretl "/home/ga/Documents/gretl_data/usa.gdt" "/home/ga/gretl_task.log"

# Wait for window
wait_for_gretl 60 || true
sleep 5

# Dismiss tips/dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize and focus
maximize_gretl
focus_gretl

# 6. Capture Initial State
mkdir -p /tmp/task_evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="