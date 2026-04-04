#!/bin/bash
set -u

echo "=== Exporting create_location_tag result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# 3. Query for the specific tag "Telehealth Endpoint"
echo "Querying Location Tag..."
TAG_RESPONSE=$(openmrs_api_get "/locationtag?q=Telehealth+Endpoint&v=full")
TAG_FOUND=$(echo "$TAG_RESPONSE" | python3 -c "import sys, json; res=json.load(sys.stdin).get('results', []); print('true' if res else 'false')")
TAG_DATA="{}"
if [ "$TAG_FOUND" == "true" ]; then
    TAG_DATA=$(echo "$TAG_RESPONSE" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['results'][0]))")
fi

# 4. Query for the location "Registration Desk" and its tags
echo "Querying Location 'Registration Desk'..."
LOC_RESPONSE=$(openmrs_api_get "/location?q=Registration+Desk&v=full")
LOC_FOUND=$(echo "$LOC_RESPONSE" | python3 -c "import sys, json; res=json.load(sys.stdin).get('results', []); print('true' if res else 'false')")
LOC_TAGS="[]"
if [ "$LOC_FOUND" == "true" ]; then
    # Extract just the tags array from the first result
    LOC_TAGS=$(echo "$LOC_RESPONSE" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['results'][0].get('tags', [])))")
fi

# 5. Check audit logs (simple approximation using API data if available, or just rely on existence)
# Note: The 'auditInfo' fields are often available in 'full' view for OpenMRS resources.
# We extracted 'full' view above.

# 6. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $EXPORT_TIME,
    "tag_found": $TAG_FOUND,
    "tag_data": $TAG_DATA,
    "location_found": $LOC_FOUND,
    "location_tags": $LOC_TAGS
}
EOF

# 7. Move to final location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="