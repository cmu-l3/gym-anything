#!/bin/bash
echo "=== Exporting soc_analyst_role_setup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

INITIAL_ROLE_STATUS=$(cat /tmp/initial_role_status 2>/dev/null || echo "000")
INITIAL_USER_STATUS=$(cat /tmp/initial_user_status 2>/dev/null || echo "000")

# Fetch Role and User details via REST API using Python
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_rest_data(endpoint):
    result = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089/services/{endpoint}?output_mode=json'],
        capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip():
        try:
            data = json.loads(result.stdout)
            entries = data.get('entry', [])
            if entries:
                return entries[0].get('content', {})
        except Exception:
            pass
    return None

role_data = get_rest_data('authorization/roles/junior_soc_analyst')
user_data = get_rest_data('authentication/users/jsmith')

output = {
    "role_exists": role_data is not None,
    "role_content": role_data if role_data else {},
    "user_exists": user_data is not None,
    "user_content": user_data if user_data else {}
}

print(json.dumps(output))
PYEOF
)

# Combine with initial states into a single result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "initial_role_http_status": "${INITIAL_ROLE_STATUS}",
    "initial_user_http_status": "${INITIAL_USER_STATUS}",
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="