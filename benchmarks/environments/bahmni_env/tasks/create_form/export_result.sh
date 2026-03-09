#!/bin/bash
echo "=== Exporting create_form task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final_state.png 2>/dev/null || true

# 2. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query OpenMRS API for the form
#    We search specifically for the target form name
TARGET_FORM="COVID-19 Screening Form"
ENCODED_QUERY=$(echo "$TARGET_FORM" | sed 's/ /%20/g')

echo "Querying OpenMRS for form: $TARGET_FORM"
FORM_RESPONSE=$(curl -sk \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/form?v=full&q=${ENCODED_QUERY}" 2>/dev/null || echo '{"results":[]}')

# 4. Check if Admin UI is visible in window title (secondary signal)
WINDOW_TITLE=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null | grep -v '@!0,0' | grep -i "epiphany" | head -1)

# 5. Create JSON result
#    We process the API response in Python to ensure safe JSON formatting
python3 -c "
import json
import sys
import time
from datetime import datetime

try:
    api_response = json.loads('''$FORM_RESPONSE''')
except:
    api_response = {'results': []}

target_name = '$TARGET_FORM'
found_form = None

# Find exact match in results
for form in api_response.get('results', []):
    if form.get('name') == target_name:
        found_form = form
        break

# If not exact match, look for partial match (case-insensitive)
if not found_form:
    for form in api_response.get('results', []):
        if target_name.lower() in form.get('name', '').lower():
            found_form = form
            break

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'form_found': found_form is not None,
    'form_data': found_form if found_form else {},
    'window_title': '''$WINDOW_TITLE''',
    'screenshot_exists': True if $TASK_END > 0 else False # logic check
}

# Add derived fields for simpler verification
if found_form:
    # Parse creation date (e.g., '2023-10-27T10:00:00.000+0000')
    date_created_str = found_form.get('auditInfo', {}).get('dateCreated', '')
    created_ts = 0
    if date_created_str:
        try:
            # Simplistic parsing, ignoring timezone for rough comparison or stripping it
            # OpenMRS dates are usually ISO8601
            dt_str = date_created_str.split('.')[0]
            dt = datetime.strptime(dt_str, '%Y-%m-%dT%H:%M:%S')
            created_ts = int(dt.timestamp())
        except Exception as e:
            pass
    
    result['created_timestamp'] = created_ts
    result['is_newly_created'] = created_ts > $TASK_START

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# 6. Secure the output file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="