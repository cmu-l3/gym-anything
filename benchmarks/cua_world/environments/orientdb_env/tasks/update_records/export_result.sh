#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting update_records results ==="

# Helper to extract value from SQL result
get_field_value() {
    local query="$1"
    local field="$2"
    orientdb_sql demodb "$query" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    r = d.get('result', [])
    if r:
        print(r[0].get('$field', 'MISSING'))
    else:
        print('NOT_FOUND')
except:
    print('ERROR')
" 2>/dev/null
}

# 1. Hotel Artemide (Stars)
FINAL_STARS=$(get_field_value "SELECT Stars FROM Hotels WHERE Name='Hotel Artemide'" "Stars")
echo "  Hotel Artemide Stars: $FINAL_STARS"

# 2. The Savoy (Phone)
FINAL_PHONE=$(get_field_value "SELECT Phone FROM Hotels WHERE Name='The Savoy'" "Phone")
echo "  The Savoy Phone: $FINAL_PHONE"

# 3. Copacabana Palace (Type)
FINAL_TYPE=$(get_field_value "SELECT Type FROM Hotels WHERE Name='Copacabana Palace'" "Type")
echo "  Copacabana Palace Type: $FINAL_TYPE"

# 4. Luca Rossi (Surname)
FINAL_SURNAME=$(get_field_value "SELECT Surname FROM Profiles WHERE Email='luca.rossi@example.com'" "Surname")
echo "  luca.rossi Surname: $FINAL_SURNAME"

# Check counts
FINAL_HOTEL_COUNT=$(get_field_value "SELECT COUNT(*) as cnt FROM Hotels" "cnt")
FINAL_PROFILE_COUNT=$(get_field_value "SELECT COUNT(*) as cnt FROM Profiles" "cnt")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Create JSON result
# Note: Python script handles JSON creation to ensure proper escaping and type handling
python3 -c "
import json
import os

result = {
    'final_artemide_stars': '$FINAL_STARS',
    'final_savoy_phone': '$FINAL_PHONE',
    'final_copacabana_type': '$FINAL_TYPE',
    'final_luca_surname': '$FINAL_SURNAME',
    'final_hotel_count': int('$FINAL_HOTEL_COUNT') if '$FINAL_HOTEL_COUNT'.isdigit() else 0,
    'final_profile_count': int('$FINAL_PROFILE_COUNT') if '$FINAL_PROFILE_COUNT'.isdigit() else 0,
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"