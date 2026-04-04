#!/bin/bash
# export_result.sh — post_task hook for register_oauth_application

echo "=== Exporting register_oauth_application result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
OUTPUT_FILE="/home/ga/Documents/skylinks_creds.txt"

# 3. Read agent's output file
FILE_EXISTS="false"
FILE_CONTENT=""
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 4. Query Database for the OAuth Application
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
    "task_start": "${TASK_START}",
    "file_exists": ${FILE_EXISTS},
    "file_content": """${FILE_CONTENT}""",
    "db_record": None,
    "error": None
}

try:
    from oauth2_provider.models import Application
    
    # Check for the specific app
    app = Application.objects.filter(name='SkyLinks GCS').order_by('-created').first()
    
    if app:
        result["db_record"] = {
            "name": app.name,
            "client_id": app.client_id,
            "client_type": app.client_type,
            "authorization_grant_type": app.authorization_grant_type,
            "user": app.user.username if app.user else None,
            "created": str(app.created),
            # Note: We don't export client_secret from DB as it might be hashed 
            # (though default DOT stores it plain usually, newer versions hash it).
            # We will rely on matching the Client ID and existence of secret in file.
        }
    else:
        print("No application named 'SkyLinks GCS' found.")

except Exception as e:
    result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic finished.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="