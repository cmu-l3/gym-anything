#!/bin/bash
echo "=== Exporting zoom_image task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

ZOOM_CHANGED="false"
CURRENT_ZOOM="1.0"

# Check for zoom change via screenshot comparison
# When zoomed, less of the image is visible (the visible portion is magnified)
if [ -f /tmp/task_start.png ] && [ -f /tmp/task_end.png ]; then
    DIFF_RESULT=$(compare -metric RMSE /tmp/task_start.png /tmp/task_end.png /tmp/diff.png 2>&1 || echo "0")
    DIFF_VALUE=$(echo "$DIFF_RESULT" | grep -oE '^[0-9.]+' || echo "0")

    if [ -n "$DIFF_VALUE" ]; then
        DIFF_INT=$(echo "$DIFF_VALUE" | cut -d'.' -f1)
        if [ "$DIFF_INT" -gt 200 ] 2>/dev/null; then
            ZOOM_CHANGED="true"
            CURRENT_ZOOM="2.0"
        elif [ "$DIFF_INT" -gt 100 ] 2>/dev/null; then
            ZOOM_CHANGED="true"
            CURRENT_ZOOM="1.5"
        fi
    fi
fi

# Check Weasis logs for zoom operations
if grep -qiE "(zoom|scale|magnif)" /tmp/weasis_ga.log 2>/dev/null; then
    ZOOM_CHANGED="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": true,
    "zoom_changed": $ZOOM_CHANGED,
    "initial_zoom": 1.0,
    "current_zoom": $CURRENT_ZOOM,
    "screenshot_diff": "${DIFF_VALUE:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
