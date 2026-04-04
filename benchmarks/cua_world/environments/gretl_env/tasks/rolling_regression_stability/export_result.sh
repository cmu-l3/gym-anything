#!/bin/bash
set -e
echo "=== Exporting Rolling Regression Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Generate Ground Truth for Verification
# We run a trusted script to generate the correct CSV for comparison
# This ensures we verify against the actual data loaded in the env
echo "Generating ground truth data..."
cat > /tmp/ground_truth_gen.inp << 'EOF'
open /home/ga/Documents/gretl_data/usa.gdt
# Create series to store results
series b_true = NA
series se_true = NA
# Loop settings
scalar window = 24
scalar T = $nobs
# Perform rolling regression
loop i=window+1..T --quiet
    smpl i-window+1 i
    ols inf const inf(-1) --quiet
    b_true[i] = $coeff(inf_1)
    se_true[i] = $stderr(inf_1)
    smpl full
endloop
# Save to CSV (filter out NAs)
smpl window+1 T --restrict
store "/tmp/ground_truth.csv" b_true se_true --csv
EOF

# Run ground truth generation (as user ga to match permissions/paths if needed)
# Using gretlcli in batch mode
su - ga -c "gretlcli -b /tmp/ground_truth_gen.inp" > /tmp/gt_gen.log 2>&1 || echo "Warning: Ground truth generation failed"

# 3. Collect Artifacts Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/gretl_output/rolling_results.csv"
PLOT_PATH="/home/ga/Documents/gretl_output/persistence_plot.png"
SCRIPT_PATH="/home/ga/Documents/gretl_output/run_rolling.inp"

# Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    # Copy to temp for export
    cp "$CSV_PATH" /tmp/agent_results.csv
else
    CSV_EXISTS="false"
    CSV_MTIME="0"
fi

# Check Plot
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH")
else
    PLOT_EXISTS="false"
    PLOT_MTIME="0"
fi

# Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | base64 -w 0)
else
    SCRIPT_EXISTS="false"
    SCRIPT_CONTENT=""
fi

# Check timestamps (Anti-gaming)
FILES_NEW="false"
if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
    FILES_NEW="true"
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "plot_exists": $PLOT_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "files_created_during_task": $FILES_NEW,
    "script_content_base64": "$SCRIPT_CONTENT",
    "ground_truth_generated": $([ -f /tmp/ground_truth.csv ] && echo "true" || echo "false")
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json /tmp/agent_results.csv /tmp/ground_truth.csv /tmp/task_final.png 2>/dev/null || true

echo "Export complete."