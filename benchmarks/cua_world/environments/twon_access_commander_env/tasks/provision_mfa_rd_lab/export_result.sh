#!/bin/bash
echo "=== Exporting provision_mfa_rd_lab task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before any windows are closed
take_screenshot /tmp/task_final.png

# Extract API data cleanly using Python
python3 << 'PYEOF'
import json
import subprocess
import os

def fetch_api(endpoint):
    """Fetches JSON payload from AC API securely using existing bash context."""
    try:
        cmd = f"source /workspace/scripts/task_utils.sh && ac_login >/dev/null 2>&1 && ac_api GET '{endpoint}'"
        output = subprocess.check_output(['/bin/bash', '-c', cmd], stderr=subprocess.DEVNULL).decode('utf-8')
        if not output.strip():
            return []
        return json.loads(output)
    except Exception as e:
        return {"error": str(e)}

# Export all relevant relational entities for offline verification
result = {
    "zones": fetch_api("/zones"),
    "rules": fetch_api("/accessRules"),
    "rules_alt": fetch_api("/access-rules"),
    "groups": fetch_api("/groups"),
    "profiles": fetch_api("/timeProfiles"),
    "profiles_alt": fetch_api("/time-profiles")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "API extraction complete. Result JSON saved to /tmp/task_result.json."
echo "=== Export complete ==="