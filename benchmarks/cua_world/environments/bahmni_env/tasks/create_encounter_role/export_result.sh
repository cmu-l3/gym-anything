#!/bin/bash
echo "=== Exporting create_encounter_role results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query OpenMRS API for the created role
echo "Searching for 'Scrub Nurse' role..."
# Note: q=Scrub Nurse handles spaces automatically in requests/curl usually, but encoding helps
ROLE_DATA=$(openmrs_api_get "/encounterrole?q=Scrub+Nurse&v=full")

# Extract details using Python for robustness
FOUND_ROLE_JSON=$(echo "$ROLE_DATA" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    # Find exact or close match in results
    target = next((r for r in results if 'scrub' in r.get('name', '').lower() and 'nurse' in r.get('name', '').lower()), None)
    if target:
        print(json.dumps(target))
    else:
        print('null')
except:
    print('null')
")

# 3. Get current count
CURRENT_DATA=$(openmrs_api_get "/encounterrole?v=default&limit=100")
CURRENT_COUNT=$(echo "$CURRENT_DATA" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")
INITIAL_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")

# 4. Check if browser/app is still running
APP_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "found_role": $FOUND_ROLE_JSON,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="