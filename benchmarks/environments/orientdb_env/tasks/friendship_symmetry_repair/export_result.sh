#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Friendship Symmetry Repair Result ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification ---

# 1. Get current edge count
CURRENT_COUNT_JSON=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend")
CURRENT_COUNT=$(echo "$CURRENT_COUNT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 2. Check for specific required reverse edges
# Maria -> John
CHECK1=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend WHERE out.Email = 'maria.garcia@example.com' AND in.Email = 'john.smith@example.com'")
HAS_REVERSE_1=$(echo "$CHECK1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Sophie -> David
CHECK2=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend WHERE out.Email = 'sophie.martin@example.com' AND in.Email = 'david.jones@example.com'")
HAS_REVERSE_2=$(echo "$CHECK2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# James -> Yuki
CHECK3=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend WHERE out.Email = 'james.brown@example.com' AND in.Email = 'yuki.tanaka@example.com'")
HAS_REVERSE_3=$(echo "$CHECK3" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 3. Check if original asymmetric edges still exist (to prevent delete-all-gaming)
# John -> Maria
CHECK_ORIG=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend WHERE out.Email = 'john.smith@example.com' AND in.Email = 'maria.garcia@example.com'")
HAS_ORIGINAL=$(echo "$CHECK_ORIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 4. Calculate total asymmetry in the graph
# (Count how many edges A->B exist where B->A does not)
SYMMETRY_JSON=$(orientdb_sql "demodb" "SELECT out.Email as src, in.Email as dst FROM HasFriend")
ASYMMETRY_COUNT=$(echo "$SYMMETRY_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
edges = set()
for r in data.get('result', []):
    s, d = r.get('src'), r.get('dst')
    if s and d: edges.add((s,d))
asym = 0
for (s,d) in edges:
    if (d,s) not in edges:
        asym += 1
print(asym)
" 2>/dev/null || echo "999")

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "has_reverse_maria_john": $HAS_REVERSE_1,
    "has_reverse_sophie_david": $HAS_REVERSE_2,
    "has_reverse_james_yuki": $HAS_REVERSE_3,
    "has_original_edge": $HAS_ORIGINAL,
    "asymmetry_count": $ASYMMETRY_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json