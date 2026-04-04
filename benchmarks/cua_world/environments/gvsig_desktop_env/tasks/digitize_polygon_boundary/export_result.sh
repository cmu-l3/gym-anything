#!/bin/bash
echo "=== Exporting digitize_polygon_boundary results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Expected output path
OUTPUT_SHP="/home/ga/gvsig_data/projects/iceland_boundary.shp"
OUTPUT_DBF="/home/ga/gvsig_data/projects/iceland_boundary.dbf"
OUTPUT_SHX="/home/ga/gvsig_data/projects/iceland_boundary.shx"

# Reference data path (for the verifier to compare against)
REF_SHP="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
REF_DBF="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"
REF_SHX="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shx"

# Check output existence
OUTPUT_EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP")
    FILE_TIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# App state
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare files for export (copy to /tmp with known names for verifier)
echo "Preparing files for verification..."

# 1. Agent's Output
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_SHP" /tmp/agent_output.shp
    cp "$OUTPUT_DBF" /tmp/agent_output.dbf 2>/dev/null || true
    cp "$OUTPUT_SHX" /tmp/agent_output.shx 2>/dev/null || true
    chmod 644 /tmp/agent_output.*
fi

# 2. Reference Data
# We copy this so the verifier (running on host) can read it
cp "$REF_SHP" /tmp/reference.shp
cp "$REF_DBF" /tmp/reference.dbf
cp "$REF_SHX" /tmp/reference.shx
chmod 644 /tmp/reference.*

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json