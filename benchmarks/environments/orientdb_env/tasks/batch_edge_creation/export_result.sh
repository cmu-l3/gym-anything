#!/bin/bash
echo "=== Exporting batch_edge_creation results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
EXPECTED_EDGES=$(cat /tmp/expected_edge_count.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- DATABASE INSPECTION ---

# 1. Check if class exists
CLASS_INFO=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null)
CLASS_EXISTS=$(echo "$CLASS_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if any(c['name']=='IsNearby' for c in d.get('classes',[])) else 'false')" 2>/dev/null || echo "false")

# 2. Check inheritance (superClass)
SUPER_CLASS=$(echo "$CLASS_INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
cls = next((c for c in d.get('classes',[]) if c['name']=='IsNearby'), {})
print(cls.get('superClass', ''))
" 2>/dev/null || echo "")

# 3. Check properties
HAS_TYPE_PROP=$(echo "$CLASS_INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
cls = next((c for c in d.get('classes',[]) if c['name']=='IsNearby'), {})
props = [p['name'] for p in cls.get('properties', [])]
print('true' if 'Type' in props else 'false')
" 2>/dev/null || echo "false")

# 4. Count total edges in IsNearby
TOTAL_EDGES=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM IsNearby" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 5. Count edges with correct Type property
CORRECT_TYPE_CNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM IsNearby WHERE Type='same_city'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 6. Validate Edge Logic (City Match)
# We count how many edges are INVALID (where cities don't match)
# Query: SELECT count(*) FROM IsNearby WHERE out.City != in.City
INVALID_CITY_MATCH=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM IsNearby WHERE out.City != in.City" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 7. Check Direction (Hotels -> Restaurants)
# Query: SELECT count(*) FROM IsNearby WHERE out.@class != 'Hotels' OR in.@class != 'Restaurants'
INVALID_DIRECTION=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM IsNearby WHERE out.@class != 'Hotels' OR in.@class != 'Restaurants'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 8. Check Firefox status
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "class_exists": $CLASS_EXISTS,
    "super_class": "$SUPER_CLASS",
    "has_type_property": $HAS_TYPE_PROP,
    "total_edges": $TOTAL_EDGES,
    "correct_type_count": $CORRECT_TYPE_CNT,
    "invalid_city_match": $INVALID_CITY_MATCH,
    "invalid_direction": $INVALID_DIRECTION,
    "expected_edges": $EXPECTED_EDGES,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="