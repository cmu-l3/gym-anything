#!/bin/bash
echo "=== Exporting configure_picker_binding results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROFILE_PATH="$SEISCOMP_ROOT/etc/scautopick/broadband_opt"
PROFILE_EXISTS="false"
PROFILE_MTIME=0
FILTER_VAL=""
TIMECORR_VAL=""
BOUND_STATIONS=""

# Check if profile was created
if [ -f "$PROFILE_PATH" ]; then
    PROFILE_EXISTS="true"
    PROFILE_MTIME=$(stat -c %Y "$PROFILE_PATH" 2>/dev/null || echo "0")
    
    # Extract values, stripping quotes and leading/trailing spaces
    FILTER_VAL=$(grep "^filter" "$PROFILE_PATH" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" || echo "")
    TIMECORR_VAL=$(grep "^timeCorrection" "$PROFILE_PATH" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || echo "")
fi

# Check which stations are bound to the profile
for sta in TOLI GSI KWP SANI BKB; do
    KEYFILE="$SEISCOMP_ROOT/etc/key/station_GE_${sta}"
    if [ -f "$KEYFILE" ]; then
        if grep -q "scautopick:broadband_opt" "$KEYFILE"; then
            BOUND_STATIONS="$BOUND_STATIONS $sta"
        fi
    fi
done

# Clean up whitespace
BOUND_STATIONS=$(echo $BOUND_STATIONS | xargs)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result using a temp file to prevent permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "profile_exists": $PROFILE_EXISTS,
    "profile_mtime": $PROFILE_MTIME,
    "filter_val": "$FILTER_VAL",
    "timecorr_val": "$TIMECORR_VAL",
    "bound_stations": "$BOUND_STATIONS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="