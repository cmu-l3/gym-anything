#!/bin/bash
set -e
echo "=== Exporting task results ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_NAME="plan_tech_training_series"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_DIVE_COUNT=$(cat /tmp/${TASK_NAME}_initial_dive_count 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/${TASK_NAME}_initial_mtime 2>/dev/null || echo "0")

# Check if application was running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_evidence/${TASK_NAME}_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/${TASK_NAME}_final.png 2>/dev/null || true

# Check main logbook file
SSRF_FILE="/home/ga/Documents/dives.ssrf"
SSRF_EXISTS="false"
SSRF_SIZE="0"
SSRF_MTIME="0"
SSRF_DIVE_COUNT="0"

if [ -f "$SSRF_FILE" ]; then
    SSRF_EXISTS="true"
    SSRF_SIZE=$(stat -c %s "$SSRF_FILE" 2>/dev/null || echo "0")
    SSRF_MTIME=$(stat -c %Y "$SSRF_FILE" 2>/dev/null || echo "0")
    SSRF_DIVE_COUNT=$(grep -c '<dive ' "$SSRF_FILE" 2>/dev/null || echo "0")
fi

# Check PDF export
PDF_FILE="/home/ga/Documents/tech_training_plan.pdf"
PDF_EXISTS="false"
PDF_SIZE="0"

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_FILE" 2>/dev/null || echo "0")
fi

# Check Subsurface config for GF settings
CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"
GF_LOW=""
GF_HIGH=""

if [ -f "$CONF_FILE" ]; then
    GF_LOW=$(grep -i 'gflow' "$CONF_FILE" 2>/dev/null | head -1 || echo "")
    GF_HIGH=$(grep -i 'gfhigh' "$CONF_FILE" 2>/dev/null | head -1 || echo "")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_dive_count": $INITIAL_DIVE_COUNT,
    "initial_mtime": $INITIAL_MTIME,
    "app_was_running": $APP_RUNNING,
    "ssrf_exists": $SSRF_EXISTS,
    "ssrf_size_bytes": $SSRF_SIZE,
    "ssrf_mtime": $SSRF_MTIME,
    "ssrf_dive_count": $SSRF_DIVE_COUNT,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "gf_low_line": "$GF_LOW",
    "gf_high_line": "$GF_HIGH"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
