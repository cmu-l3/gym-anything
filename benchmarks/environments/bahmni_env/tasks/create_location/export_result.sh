#!/bin/bash
set -u

echo "=== Exporting Create Location Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Query OpenMRS API for the created location
echo "Querying OpenMRS for 'Pediatrics Ward'..."
API_RESPONSE=$(openmrs_api_get "/location?q=Pediatrics+Ward&v=full")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/location_query_debug.json

# 3. Parse details using Python for robustness
# We extract: found status, exact name, description, tags, retired status, uuid
PYTHON_PARSER=$(cat <<EOF
import sys, json

try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    
    # Filter for exact name match if multiple partial matches returned
    target_loc = None
    for loc in results:
        if loc.get('name', '').strip() == "Pediatrics Ward":
            target_loc = loc
            break
            
    if not target_loc and results:
        # Fallback to first result if close enough (verifier will penalize mismatch)
        target_loc = results[0]

    if target_loc:
        print(json.dumps({
            "found": True,
            "uuid": target_loc.get('uuid'),
            "name": target_loc.get('name'),
            "description": target_loc.get('description'),
            "retired": target_loc.get('retired'),
            "tags": [t.get('display', '') for t in target_loc.get('tags', [])]
        }))
    else:
        print(json.dumps({"found": False}))

except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
EOF
)

LOCATION_DETAILS=$(echo "$API_RESPONSE" | python3 -c "$PYTHON_PARSER")

# 4. Get final location count
FINAL_COUNT_JSON=$(openmrs_api_get "/location?v=default&limit=100")
FINAL_COUNT=$(echo "$FINAL_COUNT_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")

# 5. Read initial count
INITIAL_COUNT=$(cat /tmp/initial_location_count.txt 2>/dev/null || echo "0")

# 6. Check if Admin UI is visible in screenshot (simple check: implies browser open)
# Real verification happens via VLM in verifier.py, but we capture the file here.
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 7. Create Task Result JSON
# Use a temp file to ensure atomic write and avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "location_details": $LOCATION_DETAILS,
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="