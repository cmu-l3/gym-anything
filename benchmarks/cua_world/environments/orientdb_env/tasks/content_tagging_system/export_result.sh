#!/bin/bash
echo "=== Exporting Content Tagging System Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/home/ga/tagging_report.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# === 1. CHECK REPORT FILE ===
REPORT_EXISTS="false"
REPORT_CONTENT="{}"
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content, verifying it's valid JSON
    if jq . "$REPORT_PATH" >/dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    else
        REPORT_CONTENT="{\"error\": \"Invalid JSON\"}"
    fi
fi

# === 2. EXTRACT DATABASE STATE ===
# We need to run queries and export the results to JSON so verifier.py can read them
# without needing exec_in_env.

echo "Querying OrientDB state..."

# Helper to run SQL and get result list
run_query() {
    local sql="$1"
    orientdb_sql "demodb" "$sql" | \
    python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('result', [])))" 2>/dev/null || echo "[]"
}

# Helper to check schema
get_schema_info() {
    curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
classes = data.get('classes', [])
schema = {
    'Tags_exists': False, 
    'HasTag_exists': False, 
    'Tags_superClass': '', 
    'HasTag_superClass': '',
    'Tags_properties': [],
    'Tags_indexes': []
}
for c in classes:
    if c['name'] == 'Tags':
        schema['Tags_exists'] = True
        schema['Tags_superClass'] = c.get('superClass', '') or (c.get('superClasses', [''])[0] if c.get('superClasses') else '')
        schema['Tags_properties'] = [p['name'] for p in c.get('properties', [])]
        schema['Tags_indexes'] = [i['name'] for i in c.get('indexes', [])]
    elif c['name'] == 'HasTag':
        schema['HasTag_exists'] = True
        schema['HasTag_superClass'] = c.get('superClass', '') or (c.get('superClasses', [''])[0] if c.get('superClasses') else '')
print(json.dumps(schema))
"
}

# A. Schema verification
SCHEMA_INFO=$(get_schema_info)

# B. Tag Data verification
# Get all tag names
TAG_NAMES=$(run_query "SELECT Name FROM Tags")

# Count edges
HASTAG_COUNT=$(run_query "SELECT COUNT(*) as count FROM HasTag" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('count', 0))")

# C. Logic verification queries (Anti-gaming and Accuracy)
# 1. Luxury check: Get stars of all hotels tagged 'luxury'
LUXURY_HOTELS_STARS=$(run_query "SELECT Stars FROM Hotels WHERE out('HasTag').Name CONTAINS 'luxury'")

# 2. Budget check: Get stars of all hotels tagged 'budget'
BUDGET_HOTELS_STARS=$(run_query "SELECT Stars FROM Hotels WHERE out('HasTag').Name CONTAINS 'budget'")

# 3. Cultural check (Italy): Count Italy entities tagged cultural vs not
ITALY_TAGGED_CULTURAL=$(run_query "SELECT COUNT(*) as c FROM V WHERE Country='Italy' AND out('HasTag').Name CONTAINS 'cultural'" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('c', 0))")
ITALY_TOTAL=$(run_query "SELECT COUNT(*) as c FROM V WHERE Country='Italy'" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('c', 0))")

# 4. Blanket tagging check: Did they just tag everything 'luxury'?
TOTAL_HOTELS=$(run_query "SELECT COUNT(*) as c FROM Hotels" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('c', 0))")
LUXURY_TAG_COUNT=$(run_query "SELECT COUNT(*) as c FROM Hotels WHERE out('HasTag').Name CONTAINS 'luxury'" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('c', 0))")

# === 3. COMPILE RESULT JSON ===
RESULT_JSON="/tmp/task_result.json"
cat > "$RESULT_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content": $REPORT_CONTENT,
    "db_schema": $SCHEMA_INFO,
    "db_data": {
        "tag_names": $TAG_NAMES,
        "hastag_count": $HASTAG_COUNT,
        "luxury_hotels_stars": $LUXURY_HOTELS_STARS,
        "budget_hotels_stars": $BUDGET_HOTELS_STARS,
        "italy_tagged_cultural": $ITALY_TAGGED_CULTURAL,
        "italy_total": $ITALY_TOTAL,
        "total_hotels": $TOTAL_HOTELS,
        "luxury_tag_count": $LUXURY_TAG_COUNT
    }
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result compiled to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="