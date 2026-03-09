#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Check if App was running
APP_WAS_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# 3. Kill Floreant POS to release DB lock for verification
echo "Stopping Floreant POS to verify database..."
kill_floreant
sleep 3
# Force kill to be sure
pkill -9 -f "floreantpos" 2>/dev/null || true
sleep 2

# 4. Run Query Tool to get Final State
DB_DIR=$(cat /tmp/floreant_db_path.txt 2>/dev/null)
DERBY_JAR=$(cat /tmp/floreant_derby_jar.txt 2>/dev/null)

# Clean locks
rm -f "$DB_DIR/db.lck" 2>/dev/null || true

echo "Querying final DB state..."
java -cp "/tmp:$DERBY_JAR" QueryRestaurant "$DB_DIR" > /tmp/restaurant_final.txt 2>/dev/null || echo "Query failed"

echo "Final Data:"
cat /tmp/restaurant_final.txt

# 5. Parse Data for JSON
# Function to get value by key from the key=value file
get_val() {
    local key=$1
    local file=$2
    grep "^$key=" "$file" | cut -d'=' -f2- | head -1
}

# Extract Baseline
BASE_NAME=$(get_val "NAME" /tmp/restaurant_baseline.txt)
BASE_ADDR=$(get_val "ADDRESS_LINE1" /tmp/restaurant_baseline.txt)
if [ -z "$BASE_ADDR" ]; then BASE_ADDR=$(get_val "ADDRESS" /tmp/restaurant_baseline.txt); fi

# Extract Final
FINAL_NAME=$(get_val "NAME" /tmp/restaurant_final.txt)
FINAL_ADDR=$(get_val "ADDRESS_LINE1" /tmp/restaurant_final.txt)
if [ -z "$FINAL_ADDR" ]; then FINAL_ADDR=$(get_val "ADDRESS" /tmp/restaurant_final.txt); fi
FINAL_ZIP=$(get_val "ZIP_CODE" /tmp/restaurant_final.txt)
FINAL_PHONE=$(get_val "TELEPHONE" /tmp/restaurant_final.txt)

# 6. Create JSON Result
# We use python to create valid JSON to avoid escaping issues
python3 -c "
import json
import os

try:
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'app_was_running': '$APP_WAS_RUNNING' == 'true',
        'screenshot_exists': os.path.exists('/tmp/task_final.png'),
        'baseline': {
            'name': '''$BASE_NAME''',
            'address': '''$BASE_ADDR'''
        },
        'final': {
            'name': '''$FINAL_NAME''',
            'address': '''$FINAL_ADDR''',
            'zip_code': '''$FINAL_ZIP''',
            'telephone': '''$FINAL_PHONE'''
        }
    }
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# 7. Permission cleanup
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="