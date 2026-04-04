#!/bin/bash
echo "=== Exporting view_metadata task result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

METADATA_VISIBLE="false"
WINDOW_TITLE=""

# Check if metadata window is visible
# Weasis opens a separate window or panel for DICOM tags
WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

# Look for metadata-related windows
if echo "$WINDOWS" | grep -qiE "(tag|metadata|header|properties|dicom|attribute)"; then
    METADATA_VISIBLE="true"
fi

# Alternative: check for visual changes indicating metadata panel
if [ -f /tmp/task_start.png ] && [ -f /tmp/task_end.png ]; then
    DIFF_RESULT=$(compare -metric RMSE /tmp/task_start.png /tmp/task_end.png /tmp/diff.png 2>&1 || echo "0")
    DIFF_VALUE=$(echo "$DIFF_RESULT" | grep -oE '^[0-9.]+' || echo "0")

    # Significant UI change might indicate panel opened
    if [ -n "$DIFF_VALUE" ]; then
        DIFF_INT=$(echo "$DIFF_VALUE" | cut -d'.' -f1)
        if [ "$DIFF_INT" -gt 500 ] 2>/dev/null; then
            METADATA_VISIBLE="true"
        fi
    fi
fi

# Check Weasis logs for metadata access
if grep -qiE "(tag|metadata|header|attribute|properties)" /tmp/weasis_ga.log 2>/dev/null; then
    METADATA_VISIBLE="true"
fi

# Get expected metadata
EXPECTED_METADATA="{}"
if [ -f /tmp/expected_metadata.json ]; then
    EXPECTED_METADATA=$(cat /tmp/expected_metadata.json)
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": true,
    "metadata_visible": $METADATA_VISIBLE,
    "screenshot_diff": "${DIFF_VALUE:-0}",
    "expected_metadata": $EXPECTED_METADATA,
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
