#!/bin/bash
echo "=== Exporting assign_p_wave_polarity results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ORIGINS=$(cat /tmp/initial_gym_origins 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Query current number of GYM origins
CURRENT_ORIGINS=$(mysql -u sysop -psysop seiscomp -B -N -e "SELECT COUNT(*) FROM Origin WHERE creationInfo_agencyID = 'GYM'" 2>/dev/null || echo "0")

# Extract the newly created GYM picks and their polarities
# If the agent assigned polarities and committed, they will appear here
PICKS_JSON="["
FIRST=1
while IFS=$'\t' read -r station polarity; do
    if [ -z "$station" ]; then continue; fi
    if [ $FIRST -eq 0 ]; then PICKS_JSON="$PICKS_JSON,"; fi
    PICKS_JSON="$PICKS_JSON {\"station\": \"$station\", \"polarity\": \"$polarity\"}"
    FIRST=0
done < <(mysql -u sysop -psysop seiscomp -B -N -e "SELECT waveformID_stationCode, IFNULL(polarity, 'null') FROM Pick WHERE creationInfo_agencyID = 'GYM' ORDER BY _oid DESC LIMIT 100" 2>/dev/null)
PICKS_JSON="$PICKS_JSON]"

# Check if scolv is still running
SCOLV_RUNNING=$(pgrep -f "scolv" > /dev/null && echo "true" || echo "false")

# Package into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_gym_origins": $INITIAL_ORIGINS,
    "current_gym_origins": $CURRENT_ORIGINS,
    "scolv_was_running": $SCOLV_RUNNING,
    "gym_picks": $PICKS_JSON,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to standard readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="