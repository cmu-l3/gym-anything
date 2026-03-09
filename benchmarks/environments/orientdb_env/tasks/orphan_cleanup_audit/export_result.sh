#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting orphan_cleanup_audit result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database State (Programmatic Verification)
# We check this INSIDE the container to get authoritative answers

# List of orphans that SHOULD have been deleted
ORPHAN_EMAILS=(
    "margaret.chen@tempmail.org" "robert.williams@oldmail.net"
    "aisha.rahman@defunct.co" "peter.novak@closed.org"
    "sarah.murphy@expired.net" "liu.wei@inactive.cn"
    "fatima.ali@removed.org" "dmitri.volkov@gone.ru"
)

ORPHAN_HOTELS=(
    "Albergo Cesari" "Pousada do Porto Freixo"
    "Ryokan Shimizu" "Hotel Neri"
)

# Check each orphan profile
PROFILES_REMAINING=0
PROFILES_DELETED=0
for email in "${ORPHAN_EMAILS[@]}"; do
    COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${email}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "1")
    if [ "$COUNT" = "0" ]; then
        PROFILES_DELETED=$((PROFILES_DELETED + 1))
    else
        PROFILES_REMAINING=$((PROFILES_REMAINING + 1))
    fi
done

# Check each orphan hotel
HOTELS_REMAINING=0
HOTELS_DELETED=0
for hname in "${ORPHAN_HOTELS[@]}"; do
    COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${hname}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "1")
    if [ "$COUNT" = "0" ]; then
        HOTELS_DELETED=$((HOTELS_DELETED + 1))
    else
        HOTELS_REMAINING=$((HOTELS_REMAINING + 1))
    fi
done

# Check integrity of non-orphan data (Anti-gaming)
CURRENT_CONNECTED_PROFILES=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles WHERE bothE().size() > 0" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

CURRENT_CONNECTED_HOTELS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE bothE().size() > 0" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Load initial counts
source /tmp/initial_connected_counts.txt 2>/dev/null || true
INITIAL_CONNECTED_PROFILES=${CONNECTED_PROFILES:-0}
INITIAL_CONNECTED_HOTELS=${CONNECTED_HOTELS:-0}

# 3. Check Report File
REPORT_PATH="/home/ga/orientdb_audit_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content safely, escaping for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": {
        "orphan_profiles_deleted": $PROFILES_DELETED,
        "orphan_profiles_remaining": $PROFILES_REMAINING,
        "orphan_hotels_deleted": $HOTELS_DELETED,
        "orphan_hotels_remaining": $HOTELS_REMAINING,
        "initial_connected_profiles": $INITIAL_CONNECTED_PROFILES,
        "current_connected_profiles": $CURRENT_CONNECTED_PROFILES,
        "initial_connected_hotels": $INITIAL_CONNECTED_HOTELS,
        "current_connected_hotels": $CURRENT_CONNECTED_HOTELS
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE,
        "content_json": $REPORT_CONTENT
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="