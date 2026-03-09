#!/bin/bash
echo "=== Exporting Assign User Role Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_UUID=$(cat /tmp/target_user_uuid.txt 2>/dev/null || echo "")

# 3. Query OpenMRS for the final state of user 'jwilson'
# We use python to safely fetch and parse the JSON
cat > /tmp/fetch_result.py << EOF
import requests
import json
import sys

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")

def fetch_result():
    result = {
        "user_found": False,
        "uuid_match": False,
        "roles": [],
        "retired": False
    }

    try:
        # Fetch user
        resp = requests.get(f"{BASE_URL}/user?q=jwilson&v=full", auth=AUTH, verify=False)
        if resp.status_code == 200:
            data = resp.json()
            results = data.get("results", [])
            
            # Find exact match
            user = next((u for u in results if u["username"] == "jwilson"), None)
            
            if user:
                result["user_found"] = True
                result["current_uuid"] = user["uuid"]
                result["retired"] = user.get("retired", False)
                
                # Extract role names
                result["roles"] = [r["display"] for r in user.get("roles", [])]
                
    except Exception as e:
        result["error"] = str(e)

    print(json.dumps(result))

if __name__ == "__main__":
    fetch_result()
EOF

# Run the fetch script and capture output
API_RESULT=$(python3 /tmp/fetch_result.py)

# 4. Construct Final JSON Result
# Combine file checks + API results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "original_uuid": "$ORIGINAL_UUID",
    "api_result": $API_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="