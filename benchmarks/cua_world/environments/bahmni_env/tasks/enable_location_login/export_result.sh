#!/bin/bash
echo "=== Exporting Enable Location Login Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 2. Query OpenMRS API for the Target Location
TARGET_LOC="Telemedicine Wing"
echo "Querying OpenMRS for location: $TARGET_LOC"

# Fetch full details including audit info and tags
API_RESPONSE=$(openmrs_api_get "/location?q=Telemedicine+Wing&v=full")

# Save raw response for debugging/backup
echo "$API_RESPONSE" > /tmp/raw_location_response.json

# 3. Extract relevant data using Python
# We need to handle the search result list and find the exact match
PYTHON_PARSER=$(cat <<END
import sys, json, datetime

try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    
    # Filter for exact name match (case-insensitive)
    target_name = "$TARGET_LOC".lower()
    location = next((r for r in results if r.get('name', '').lower() == target_name), None)
    
    output = {
        "location_found": False,
        "uuid": None,
        "retired": False,
        "tags": [],
        "date_changed": None,
        "date_created": None
    }
    
    if location:
        output["location_found"] = True
        output["uuid"] = location.get("uuid")
        output["retired"] = location.get("retired", False)
        
        # Extract tag display names
        tags = location.get("tags", [])
        output["tags"] = [t.get("display", "") for t in tags]
        
        # Extract audit timestamps
        # OpenMRS dates are usually ISO8601 strings e.g. "2023-10-27T10:00:00.000+0000"
        audit = location.get("auditInfo", {})
        output["date_changed"] = audit.get("dateChanged")
        output["date_created"] = audit.get("dateCreated")

    print(json.dumps(output))

except Exception as e:
    print(json.dumps({"error": str(e)}))
END
)

PARSED_RESULT=$(echo "$API_RESPONSE" | python3 -c "$PYTHON_PARSER")

# 4. Create Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "api_data": $PARSED_RESULT
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="