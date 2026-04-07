#!/bin/bash
echo "=== Exporting tune_picker_sensitivity results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / visual evidence
take_screenshot /tmp/task_end.png

# ─── 1. Gather Pick Counts ───────────────────────────────────────────────────
INITIAL_PICKS=$(cat /tmp/initial_pick_count 2>/dev/null || echo "0")
FINAL_PICKS=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Pick WHERE stream_stationCode='KWP'" 2>/dev/null || echo "0")

# ─── 2. Read Configuration for trigOn ────────────────────────────────────────
PROFILE_FILE="$SEISCOMP_ROOT/etc/key/scautopick/profile_HighThreshold/config"
if [ -f "$PROFILE_FILE" ]; then
    # Extract the trigOn value, stripping whitespace
    TRIG_ON=$(grep -E "^trigOn\s*=" "$PROFILE_FILE" | cut -d'=' -f2 | tr -d ' ' 2>/dev/null)
else
    TRIG_ON="not_found"
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ─── 3. Export to JSON ───────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/tune_picker_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_picks": $INITIAL_PICKS,
    "final_picks": $FINAL_PICKS,
    "trig_on": "$TRIG_ON",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/tune_picker_result.json 2>/dev/null || sudo rm -f /tmp/tune_picker_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tune_picker_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tune_picker_result.json
chmod 666 /tmp/tune_picker_result.json 2>/dev/null || sudo chmod 666 /tmp/tune_picker_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/tune_picker_result.json"
cat /tmp/tune_picker_result.json
echo "=== Export complete ==="