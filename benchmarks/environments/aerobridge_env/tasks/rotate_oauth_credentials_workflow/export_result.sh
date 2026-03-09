#!/bin/bash
# export_result.sh — post_task hook for rotate_oauth_credentials_workflow

echo "=== Exporting rotate_oauth_credentials_workflow result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check the Credentials File
CRED_FILE="/home/ga/Documents/new_credentials.json"
FILE_EXISTS="false"
FILE_CONTENT="{}"

if [ -f "$CRED_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, removing newlines for safe JSON embedding
    FILE_CONTENT=$(cat "$CRED_FILE" | tr -d '\n')
fi

# 3. Query Database State
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

result = {
    "v1_exists": False,
    "v2_exists": False,
    "v2_config": {},
    "file_exists": $FILE_EXISTS,
    "file_content_raw": '$FILE_CONTENT',
    "task_start_time": "$(cat /tmp/task_start_time 2>/dev/null)",
    "error": None
}

try:
    from oauth2_provider.models import Application
    
    # Check V1 (Should be deleted)
    result["v1_exists"] = Application.objects.filter(name='Logistics_Fleet_Sync_v1').exists()
    
    # Check V2 (Should be created)
    v2_app = Application.objects.filter(name='Logistics_Fleet_Sync_v2').first()
    
    if v2_app:
        result["v2_exists"] = True
        result["v2_config"] = {
            "client_id": v2_app.client_id,
            "client_secret": v2_app.client_secret,
            "client_type": v2_app.client_type,
            "authorization_grant_type": v2_app.authorization_grant_type,
            "redirect_uris": v2_app.redirect_uris,
            "created_at": str(v2_app.created)
        }
    
    # Parse the user's JSON file to check against DB
    try:
        if result["file_exists"]:
            import json as j
            # The raw content might be messy, try to parse
            raw = result["file_content_raw"]
            if raw:
                user_json = j.loads(raw)
                result["file_parsed"] = user_json
    except Exception as e:
        result["file_parse_error"] = str(e)

except Exception as e:
    result["error"] = str(e)

# Save to /tmp/task_result.json
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="