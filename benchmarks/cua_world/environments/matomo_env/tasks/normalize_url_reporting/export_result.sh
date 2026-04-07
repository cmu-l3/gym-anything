#!/bin/bash
# Export script for Normalize URL Reporting task

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Initial State to get IDs
CONTROL_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json'))['control_site']['idsite'])" 2>/dev/null)
TARGET_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json'))['target_site']['idsite'])" 2>/dev/null)

echo "Control ID: $CONTROL_ID"
echo "Target ID: $TARGET_ID"

# ── Query Current Configuration ───────────────────────────────────────────

# Helper to escape JSON string
json_escape() {
    echo -n "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# Get current Control Site state
CONTROL_RES=$(matomo_query "SELECT excluded_parameters, keep_url_fragment FROM matomo_site WHERE idsite=$CONTROL_ID" 2>/dev/null)
CONTROL_PARAMS=$(echo "$CONTROL_RES" | cut -f1)
CONTROL_FRAG=$(echo "$CONTROL_RES" | cut -f2)

# Get current Target Site state
TARGET_RES=$(matomo_query "SELECT excluded_parameters, keep_url_fragment FROM matomo_site WHERE idsite=$TARGET_ID" 2>/dev/null)
TARGET_PARAMS=$(echo "$TARGET_RES" | cut -f1)
TARGET_FRAG=$(echo "$TARGET_RES" | cut -f2)

# Get baseline for comparison (to detect changes)
BASELINE_CONTROL_PARAMS=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json'))['control_site']['excluded_parameters'])" 2>/dev/null)
BASELINE_CONTROL_FRAG=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json'))['control_site']['keep_url_fragment'])" 2>/dev/null)

# Check if Control Site was modified
CONTROL_MODIFIED="false"
if [ "$CONTROL_PARAMS" != "$BASELINE_CONTROL_PARAMS" ] || [ "$CONTROL_FRAG" != "$BASELINE_CONTROL_FRAG" ]; then
    CONTROL_MODIFIED="true"
    echo "WARNING: Control site modified!"
fi

# ── Create Result JSON ────────────────────────────────────────────────────
cat > /tmp/task_result.json << EOF
{
    "control_site": {
        "id": "$CONTROL_ID",
        "modified": $CONTROL_MODIFIED,
        "current_params": $(json_escape "$CONTROL_PARAMS"),
        "current_fragment": "$CONTROL_FRAG"
    },
    "target_site": {
        "id": "$TARGET_ID",
        "current_params": $(json_escape "$TARGET_PARAMS"),
        "current_fragment": "$TARGET_FRAG"
    },
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete:"
cat /tmp/task_result.json