#!/bin/bash
# Export: configure_location_tags task
# Queries the location configuration to check for applied tags.

echo "=== Exporting configure_location_tags result ==="
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the Location UUID (re-fetch to be safe)
LOC_UUID=$(omrs_get "/location?q=Isolation+Ward&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

# 2. Fetch the full location details including tags
echo "Fetching location details..."
LOCATION_JSON=$(omrs_get "/location/$LOC_UUID?v=full")

# 3. Extract the tags
TAGS_FOUND=$(echo "$LOCATION_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tags = [t.get('display', '') for t in data.get('tags', [])]
    print(json.dumps(tags))
except Exception:
    print('[]')
")

# 4. Check if location is retired (should not be)
IS_RETIRED=$(echo "$LOCATION_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('retired', False))" 2>/dev/null || echo "False")

# 5. Prepare export JSON
TEMP_JSON=$(mktemp /tmp/loc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "location_uuid": "$LOC_UUID",
    "location_name": "Isolation Ward",
    "found_tags": $TAGS_FOUND,
    "is_retired": $IS_RETIRED,
    "initial_tag_count": $(cat /tmp/initial_tag_count 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="