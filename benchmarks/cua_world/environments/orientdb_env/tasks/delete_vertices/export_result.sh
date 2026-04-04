#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting delete_vertices results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Wait for OrientDB just in case
wait_for_orientdb 30

# 1. Check if targets are deleted
TARGETS=("Copacabana Palace" "Park Hyatt Tokyo" "Four Seasons Sydney")
DELETED_STATUS="{"
FIRST=true
for HOTEL in "${TARGETS[@]}"; do
    COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Name = '${HOTEL}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "1")
    
    if [ "$FIRST" = "true" ]; then FIRST=false; else DELETED_STATUS="${DELETED_STATUS}, "; fi
    DELETED_STATUS="${DELETED_STATUS}\"${HOTEL}\": ${COUNT}"
done
DELETED_STATUS="${DELETED_STATUS}}"

# 2. Check total count
FINAL_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_hotel_count.txt 2>/dev/null || echo "0")

# 3. Check survivors (spot check)
SURVIVORS=("Hotel Artemide" "The Savoy")
SURVIVOR_STATUS="{"
FIRST=true
for HOTEL in "${SURVIVORS[@]}"; do
    COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Name = '${HOTEL}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
    if [ "$FIRST" = "true" ]; then FIRST=false; else SURVIVOR_STATUS="${SURVIVOR_STATUS}, "; fi
    SURVIVOR_STATUS="${SURVIVOR_STATUS}\"${HOTEL}\": ${COUNT}"
done
SURVIVOR_STATUS="${SURVIVOR_STATUS}}"

# 4. Check for orphaned edges (HasStayed, HasReview)
# If DELETE VERTEX was used, these should be 0. If DELETE FROM Hotels was used, edges might remain.
STAYED_ORPHANS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasStayed WHERE out IS NULL OR in IS NULL" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
REVIEW_ORPHANS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasReview WHERE out IS NULL OR in IS NULL" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check if application was running
APP_RUNNING=$(pgrep -f "orientdb" > /dev/null && echo "true" || echo "false")
BROWSER_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "deleted_targets": $DELETED_STATUS,
    "survivors": $SURVIVOR_STATUS,
    "orphaned_edges": {
        "HasStayed": $STAYED_ORPHANS,
        "HasReview": $REVIEW_ORPHANS
    },
    "app_running": $APP_RUNNING,
    "browser_running": $BROWSER_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png"
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