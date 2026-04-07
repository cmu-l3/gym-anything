#!/bin/bash
echo "=== Exporting clean_orphan_origins_db result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ─── 1. Check Output File ────────────────────────────────────────────────────
OUTPUT_FILE="/home/ga/orphan_origins.txt"
FILE_EXISTS="false"
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"
FILE_CONTENTS=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read contents, strip quotes and whitespace, join with commas
    FILE_CONTENTS=$(cat "$OUTPUT_FILE" | tr -d '"' | tr -d "'" | awk '{$1=$1};1' | grep -v '^\s*$' | tr '\n' ',' | sed 's/,$//')
fi

# ─── 2. Query Database State ─────────────────────────────────────────────────

# Target injected orphans
TARGET_ORPHANS="'smi:org/gfz/orphan_test_1', 'smi:org/gfz/orphan_test_2', 'smi:org/gfz/orphan_test_3'"

# Check how many injected orphans remain
TARGETS_REMAINING=$(mysql -u sysop -psysop seiscomp -N -B -e "
    SELECT COUNT(*) 
    FROM Origin o 
    JOIN PublicObject po ON o._oid = po._oid 
    WHERE po.publicID IN ($TARGET_ORPHANS)
" 2>/dev/null || echo "-1")

# Check total orphans remaining
# (Orphans: Origin exists, but publicID not referenced in OriginReference.originID and not in Event.preferredOriginID)
TOTAL_ORPHANS_REMAINING=$(mysql -u sysop -psysop seiscomp -N -B -e "
    SELECT COUNT(*) 
    FROM Origin o
    JOIN PublicObject po ON o._oid = po._oid
    WHERE po.publicID NOT IN (SELECT originID FROM OriginReference)
    AND po.publicID NOT IN (SELECT preferredOriginID FROM Event WHERE preferredOriginID IS NOT NULL)
" 2>/dev/null || echo "-1")

# Check valid events (to ensure the agent didn't blow away the whole catalog)
VALID_EVENTS_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "-1")

# ─── 3. Create Result JSON ───────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_contents": "$FILE_CONTENTS",
    "targets_remaining": $TARGETS_REMAINING,
    "total_orphans_remaining": $TOTAL_ORPHANS_REMAINING,
    "valid_events_count": $VALID_EVENTS_COUNT,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
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