#!/bin/bash
# Export script for GDPR Erasure Task

echo "=== Exporting GDPR Erasure Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Load initial state
TARGET_ID="34c4f238a0b92382"
if [ -f /tmp/gdpr_initial_state.json ]; then
    # Try to extract target ID from json if python is available, else use default
    EXTRACTED_ID=$(python3 -c "import json; print(json.load(open('/tmp/gdpr_initial_state.json')).get('target_id', '$TARGET_ID'))" 2>/dev/null)
    if [ -n "$EXTRACTED_ID" ]; then TARGET_ID="$EXTRACTED_ID"; fi
fi

# Query current database state
# 1. Check if target still exists
FINAL_TARGET_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) = UPPER('$TARGET_ID')")

# 2. Check if other users still exist (Collateral Damage check)
FINAL_OTHER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit WHERE hex(idvisitor) != UPPER('$TARGET_ID')")

# 3. Check total count
FINAL_TOTAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_log_visit")

echo "Final State:"
echo "  Target ID: $TARGET_ID"
echo "  Target Records Remaining: $FINAL_TARGET_COUNT"
echo "  Other Records Remaining: $FINAL_OTHER_COUNT"
echo "  Total Records: $FINAL_TOTAL_COUNT"

# Load initial values for delta calculation
INITIAL_TARGET_COUNT=0
if [ -f /tmp/gdpr_initial_state.json ]; then
    INITIAL_TARGET_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/gdpr_initial_state.json')).get('initial_target_count', 0))" 2>/dev/null)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/gdpr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_id": "$TARGET_ID",
    "final_target_count": ${FINAL_TARGET_COUNT:-0},
    "final_other_count": ${FINAL_OTHER_COUNT:-0},
    "final_total_count": ${FINAL_TOTAL_COUNT:-0},
    "initial_target_count": ${INITIAL_TARGET_COUNT:-0},
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/gdpr_erasure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gdpr_erasure_result.json
chmod 666 /tmp/gdpr_erasure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/gdpr_erasure_result.json"
cat /tmp/gdpr_erasure_result.json
echo "=== Export Complete ==="