#!/bin/bash
set -e
echo "=== Exporting Video Wall Task Result ==="

source /workspace/scripts/task_utils.sh

# Refresh token for queries
TOKEN=$(refresh_nx_token)

# 1. Capture Final State Data via API
# We dump the full JSON responses to a file so the verifier (on host) can parse them.

# Get all Video Walls
VW_JSON=$(nx_api_get "/rest/v1/videoWalls")

# Get all Layouts
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts")

# Get Report Content
REPORT_CONTENT=""
if [ -f /home/ga/video_wall_report.txt ]; then
    REPORT_CONTENT=$(cat /home/ga/video_wall_report.txt | base64 -w 0)
fi

# Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get Initial Counts
INITIAL_VW_COUNT=$(cat /tmp/initial_vw_count.txt 2>/dev/null || echo "0")
INITIAL_LAYOUT_COUNT=$(cat /tmp/initial_layout_count.txt 2>/dev/null || echo "0")

# Capture Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 2. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_vw_count": $INITIAL_VW_COUNT,
    "initial_layout_count": $INITIAL_LAYOUT_COUNT,
    "video_walls": $VW_JSON,
    "layouts": $LAYOUTS_JSON,
    "report_content_b64": "$REPORT_CONTENT",
    "report_exists": $([ -f /home/ga/video_wall_report.txt ] && echo "true" || echo "false"),
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 3. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"