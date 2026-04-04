#!/bin/bash
echo "=== Exporting import_time_series_csv result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

GDT_PATH="/home/ga/Documents/gretl_output/us_macro_ts.gdt"
PLOT_PATH="/home/ga/Documents/gretl_output/gdp_plot.png"

# =====================================================================
# Capture State
# =====================================================================
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Check GDT file
GDT_EXISTS="false"
GDT_SIZE="0"
if [ -f "$GDT_PATH" ]; then
    GDT_EXISTS="true"
    GDT_SIZE=$(stat -c%s "$GDT_PATH" 2>/dev/null || echo "0")
fi

# Check Plot file
PLOT_EXISTS="false"
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
fi

# =====================================================================
# Create JSON Result
# =====================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gdt_exists": $GDT_EXISTS,
    "gdt_path": "$GDT_PATH",
    "gdt_size": $GDT_SIZE,
    "plot_exists": $PLOT_EXISTS,
    "plot_path": "$PLOT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="