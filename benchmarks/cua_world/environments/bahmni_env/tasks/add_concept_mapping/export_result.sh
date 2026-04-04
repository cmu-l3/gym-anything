#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MALARIA_UUID=$(cat /tmp/malaria_concept_uuid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

if [ -z "$MALARIA_UUID" ]; then
    echo "ERROR: Malaria UUID not found from setup"
    # Try to fetch it again as fallback
    MALARIA_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/concept?q=Malaria&v=default" | \
      python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')" 2>/dev/null)
fi

echo "Verifying mappings for Concept UUID: $MALARIA_UUID"

# Fetch full concept details to inspect mappings
API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept/${MALARIA_UUID}?v=custom:(uuid,display,mappings:(uuid,mapType:(name),conceptReferenceTerm:(code,conceptSource:(name))))" 2>/dev/null)

# Parse response with Python to extract specific mapping details
# We look for: Code=61462000, Source=SNOMED CT, MapType=SAME-AS
PYTHON_PARSER=$(cat <<EOF
import json, sys

try:
    data = json.loads(sys.argv[1])
    mappings = data.get('mappings', [])
    
    found = False
    details = {
        "mapping_uuid": None,
        "code": None,
        "source": None,
        "map_type": None
    }
    
    target_code = "61462000"
    
    # Iterate to find the specific code
    for m in mappings:
        term = m.get('conceptReferenceTerm', {})
        code = term.get('code', "")
        
        if code == target_code:
            found = True
            details["mapping_uuid"] = m.get('uuid')
            details["code"] = code
            details["source"] = term.get('conceptSource', {}).get('name')
            details["map_type"] = m.get('mapType', {}).get('name')
            # If we find exact match on everything, break, otherwise keep looking
            # (In case there are multiple mappings for some reason)
            if details["source"] == "SNOMED CT" and details["map_type"] == "SAME-AS":
                break
                
    result = {
        "concept_found": True,
        "mapping_found": found,
        "details": details
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"concept_found": False, "error": str(e)}))
EOF
)

PARSED_RESULT=$(python3 -c "$PYTHON_PARSER" "$API_RESPONSE")

# Check app running state
APP_RUNNING=$(pgrep -f "epiphany" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "verification_data": $PARSED_RESULT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="