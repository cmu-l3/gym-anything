#!/bin/bash
set -e

echo "=== Exporting Configure Xfer Presets result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for Result
echo "Querying database for presets..."
# We export the full rows as JSON for the verifier to parse
# Columns: preset_name, preset_number, preset_dtmf, preset_hide_number
PRESETS_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "SELECT preset_name, preset_number, preset_dtmf, preset_hide_number FROM vicidial_xfer_presets WHERE campaign_id='SALESTEAM' ORDER BY preset_name;" \
  | python3 -c '
import sys, csv, json

reader = csv.DictReader(sys.stdin, delimiter="\t")
rows = list(reader)
print(json.dumps(rows))
' 2>/dev/null || echo "[]")

# 4. Check initial count
INITIAL_COUNT=$(cat /tmp/initial_preset_count.txt 2>/dev/null || echo "0")

# 5. Check if browser is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_presets": $PRESETS_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json