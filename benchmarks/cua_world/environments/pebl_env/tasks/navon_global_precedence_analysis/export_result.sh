#!/bin/bash
set -e
echo "=== Exporting navon_global_precedence_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record end time
date +%s > /tmp/task_end_timestamp

# Final state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Check if plot was newly created
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PLOT_PATH="/home/ga/pebl/analysis/navon_interaction_plot.png"
PLOT_EXISTS="false"
PLOT_CREATED_DURING_TASK="false"

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING_TASK="true"
    fi
fi

# Export metadata safely via temp file
TEMP_JSON=$(mktemp /tmp/navon_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING_TASK
}
EOF

rm -f /tmp/navon_meta.json
cp "$TEMP_JSON" /tmp/navon_meta.json
chmod 666 /tmp/navon_meta.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="