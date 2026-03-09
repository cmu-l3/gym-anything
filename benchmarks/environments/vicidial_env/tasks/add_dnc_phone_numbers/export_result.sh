#!/bin/bash
set -e

echo "=== Exporting DNC task results ==="

source /workspace/scripts/task_utils.sh

# ------------------------------------------------------------------
# Capture Final State
# ------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ------------------------------------------------------------------
# Verification Logic: Check Database
# ------------------------------------------------------------------
EXPECTED_FILE="/tmp/expected_dnc_numbers.txt"
FOUND_COUNT=0
TOTAL_EXPECTED=0
MISSING_NUMBERS=""

if [ -f "$EXPECTED_FILE" ]; then
    TOTAL_EXPECTED=$(wc -l < "$EXPECTED_FILE")
    
    # Check each number
    while IFS= read -r phone; do
        # Strip whitespace
        phone=$(echo "$phone" | tr -d '[:space:]')
        [ -z "$phone" ] && continue
        
        # Query DB
        EXISTS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
            "SELECT COUNT(*) FROM vicidial_dnc WHERE phone_number='$phone';" 2>/dev/null || echo "0")
            
        if [ "$EXISTS" -ge 1 ]; then
            FOUND_COUNT=$((FOUND_COUNT + 1))
        else
            MISSING_NUMBERS="$MISSING_NUMBERS $phone"
        fi
    done < "$EXPECTED_FILE"
else
    echo "ERROR: Expected numbers file missing!"
fi

# Check Total Count Increase
INITIAL_COUNT=$(cat /tmp/initial_dnc_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_dnc;" 2>/dev/null || echo "0")
COUNT_INCREASE=$((CURRENT_COUNT - INITIAL_COUNT))

# Check App State
APP_RUNNING="false"
if pgrep -f firefox >/dev/null; then
    APP_RUNNING="true"
fi

# ------------------------------------------------------------------
# Export to JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "numbers_found_count": $FOUND_COUNT,
    "numbers_expected_count": $TOTAL_EXPECTED,
    "missing_numbers": "$(echo $MISSING_NUMBERS | xargs)",
    "initial_dnc_count": $INITIAL_COUNT,
    "current_dnc_count": $CURRENT_COUNT,
    "count_increase": $COUNT_INCREASE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="