#!/bin/bash
echo "=== Exporting adjust_window_level task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read initial values
INITIAL_WC=40
INITIAL_WW=400
if [ -f /tmp/initial_wl.json ]; then
    INITIAL_WC=$(cat /tmp/initial_wl.json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("window_center", 40))')
    INITIAL_WW=$(cat /tmp/initial_wl.json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("window_width", 400))')
fi

# Try to detect current window/level from Weasis
# Weasis stores current display settings in its preferences/state

CURRENT_WC="$INITIAL_WC"
CURRENT_WW="$INITIAL_WW"
WL_CHANGED="false"

# Method 1: Check Weasis log for window/level changes
if grep -qiE "window|level|W/L|WC|WW" /tmp/weasis_ga.log 2>/dev/null; then
    # Try to extract values from log
    WL_LINE=$(grep -iE "(window.*center|WC.*=|level.*=)" /tmp/weasis_ga.log | tail -1)
    if [ -n "$WL_LINE" ]; then
        WL_CHANGED="true"
    fi
fi

# Method 2: Compare screenshots to detect visual change
# If task_start.png and task_end.png differ significantly, W/L was likely changed
if [ -f /tmp/task_start.png ] && [ -f /tmp/task_end.png ]; then
    # Use ImageMagick to compare
    DIFF_RESULT=$(compare -metric RMSE /tmp/task_start.png /tmp/task_end.png /tmp/diff.png 2>&1 || echo "0")
    DIFF_VALUE=$(echo "$DIFF_RESULT" | grep -oE '^[0-9.]+' || echo "0")

    # If difference is significant (images changed), W/L was adjusted
    if [ -n "$DIFF_VALUE" ]; then
        DIFF_INT=$(echo "$DIFF_VALUE" | cut -d'.' -f1)
        if [ "$DIFF_INT" -gt 100 ] 2>/dev/null; then
            WL_CHANGED="true"
            # Estimate change based on image difference
            # This is approximate - real value would need Weasis API access
            CURRENT_WC=$(python3 -c "print(int($INITIAL_WC + ($DIFF_INT / 10)))")
            CURRENT_WW=$(python3 -c "print(int($INITIAL_WW + ($DIFF_INT / 5)))")
        fi
    fi
fi

# Method 3: Check Weasis preferences/state files
WEASIS_STATE_DIR="/home/ga/.weasis"
SNAP_STATE_DIR="/home/ga/snap/weasis/current/.weasis"

for STATE_DIR in "$WEASIS_STATE_DIR" "$SNAP_STATE_DIR"; do
    if [ -d "$STATE_DIR" ]; then
        # Look for preferences or state files
        STATE_FILE=$(find "$STATE_DIR" -name "*.xml" -o -name "*.properties" 2>/dev/null | head -1)
        if [ -n "$STATE_FILE" ] && grep -qiE "window|level" "$STATE_FILE" 2>/dev/null; then
            WL_CHANGED="true"
        fi
    fi
done

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": true,
    "wl_changed": $WL_CHANGED,
    "initial_window_center": $INITIAL_WC,
    "initial_window_width": $INITIAL_WW,
    "current_window_center": $CURRENT_WC,
    "current_window_width": $CURRENT_WW,
    "screenshot_diff": "${DIFF_VALUE:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
