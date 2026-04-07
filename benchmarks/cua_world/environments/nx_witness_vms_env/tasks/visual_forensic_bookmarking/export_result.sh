#!/bin/bash
echo "=== Exporting Visual Forensic Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# 1. Fetch System State
# ==============================================================================

# Get Bookmarks
# API: GET /rest/v1/bookmarks
echo "Fetching bookmarks..."
BOOKMARKS_JSON=$(nx_api_get "/rest/v1/bookmarks")

# Get Camera Info (to verify name)
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")

# Read Ground Truth (requires root read access, script runs as root)
GT_START=$(cat /var/lib/nx_witness_ground_truth/alert_start.txt 2>/dev/null || echo "0")
GT_DURATION=$(cat /var/lib/nx_witness_ground_truth/alert_duration.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# 2. Package Result
# ==============================================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ground_truth_start_sec": $GT_START,
    "ground_truth_duration_sec": $GT_DURATION,
    "bookmarks": $BOOKMARKS_JSON,
    "devices": $DEVICES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"