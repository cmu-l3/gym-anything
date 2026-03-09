#!/bin/bash
echo "=== Exporting VAR task result ==="

source /workspace/scripts/task_utils.sh

# Paths
PLOT_PATH="/home/ga/Documents/gretl_output/irf_plot.png"
DATA_PATH="/home/ga/Documents/gretl_output/irf_data.csv"
GT_PATH="/var/lib/gretl/ground_truth/gt_irf.csv"

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Check Outputs
PLOT_EXISTS="false"
DATA_EXISTS="false"
PLOT_SIZE=0
DATA_SIZE=0

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c%s "$PLOT_PATH")
fi

if [ -f "$DATA_PATH" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c%s "$DATA_PATH")
fi

# 3. Check if Gretl is running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# 4. Prepare files for verification
# Copy user outputs to temp for extraction by verifier
if [ "$DATA_EXISTS" = "true" ]; then
    cp "$DATA_PATH" /tmp/agent_irf.csv
    chmod 644 /tmp/agent_irf.csv
fi

# Copy ground truth for extraction
if [ -f "$GT_PATH" ]; then
    cp "$GT_PATH" /tmp/gt_irf.csv
    chmod 644 /tmp/gt_irf.csv
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "plot_exists": $PLOT_EXISTS,
    "plot_size": $PLOT_SIZE,
    "data_exists": $DATA_EXISTS,
    "data_size": $DATA_SIZE,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date +%s)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete."