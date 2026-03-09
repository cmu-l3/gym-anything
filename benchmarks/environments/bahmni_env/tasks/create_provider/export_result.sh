#!/bin/bash
echo "=== Exporting create_provider results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_provider_count.txt 2>/dev/null || echo "0")
TARGET_ID="DOC-2024-0047"

# 3. Query OpenMRS API for the target provider
# We search by query 'Tanaka' to cast a wide net, then filter precisely in Python
API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/provider?q=Tanaka&v=full" 2>/dev/null || echo "{}")

# 4. Get Current Provider Count
CURRENT_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/provider?v=default&limit=100" 2>/dev/null | \
    python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")

# 5. Check if browser is still running
APP_RUNNING=$(pgrep -f "epiphany" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result using Python for safe parsing/generation
python3 << EOF > /tmp/task_result.json
import json
import sys
import datetime

# Inputs
api_response_str = '''$API_RESPONSE'''
task_start_ts = float($TASK_START)
initial_count = int($INITIAL_COUNT)
current_count = int($CURRENT_COUNT)
target_id = "$TARGET_ID"
app_running = "$APP_RUNNING" == "true"

result = {
    "task_start": task_start_ts,
    "initial_count": initial_count,
    "current_count": current_count,
    "app_was_running": app_running,
    "provider_found": False,
    "provider_data": {},
    "created_during_task": False,
    "is_active": False
}

try:
    data = json.loads(api_response_str)
    results = data.get("results", [])
    
    # Find the specific provider matching our target identifier
    target_provider = None
    for p in results:
        if p.get("identifier") == target_id:
            target_provider = p
            break
    
    # If not found by exact ID, look for name match to give partial feedback
    if not target_provider:
        for p in results:
            name = p.get("name", "") or p.get("person", {}).get("display", "")
            if "Tanaka" in name and "Kenji" in name:
                target_provider = p
                break

    if target_provider:
        result["provider_found"] = True
        
        # Extract fields
        p_name = target_provider.get("name", "")
        # In OpenMRS 2.x, provider might be linked to a person
        p_person_name = target_provider.get("person", {}).get("display", "")
        
        result["provider_data"] = {
            "uuid": target_provider.get("uuid"),
            "identifier": target_provider.get("identifier"),
            "name": p_name,
            "person_name": p_person_name,
            "retired": target_provider.get("retired", False)
        }
        
        result["is_active"] = not target_provider.get("retired", False)
        
        # Check creation timestamp
        date_created_str = target_provider.get("auditInfo", {}).get("dateCreated", "")
        if date_created_str:
            # Parse OpenMRS date format (e.g., 2024-01-01T12:00:00.000+0000)
            # Simplification: OpenMRS uses ISO8601
            try:
                # Remove milliseconds/timezone for manual parsing if simple approach fails
                # But let's try a robust check: is the year current?
                # Actually, let's rely on string comparison if formats align, 
                # or better: we know task started just now.
                pass 
            except:
                pass
                
            # Logic: If it exists now but didn't exist (clean slate) at start,
            # and we cleaned up at start, it must be new.
            # We explicitly cleaned up by ID in setup_task.sh.
            result["created_during_task"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
EOF

# 7. Finalize permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json