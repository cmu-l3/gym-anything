#!/bin/bash
set -euo pipefail
# Source shared utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { :; }
fi

echo "=== Exporting repair_orphaned_patient_records results ==="

# Load the GUIDs used in setup
if [ -f /tmp/task_config.sh ]; then
    source /tmp/task_config.sh
else
    echo "ERROR: Task config not found!"
    exit 1
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_INDEX_COUNT=$(cat /tmp/initial_index_count.txt 2>/dev/null || echo "0")

# --- DATABASE STATE CHECKS ---

# Helper to run MySQL query and return JSON string or null
query_index() {
    local guid="$1"
    local res
    res=$(mysql -u root DrTuxTest -N -e "SELECT FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" 2>/dev/null | head -1)
    if [ -n "$res" ]; then
        local nom=$(echo "$res" | awk '{print $1}')
        local prenom=$(echo "$res" | awk '{print $2}')
        local type=$(echo "$res" | awk '{print $3}')
        echo "{\"exists\": true, \"nom\": \"$nom\", \"prenom\": \"$prenom\", \"type\": \"$type\"}"
    else
        echo "{\"exists\": false}"
    fi
}

# Check Orphans
DUPONT_STATE=$(query_index "$GUID_DUPONT")
BERNARD_STATE=$(query_index "$GUID_BERNARD")
MOREAU_STATE=$(query_index "$GUID_MOREAU")

# Check Controls
MARTIN_STATE=$(query_index "$GUID_MARTIN")
LEROY_STATE=$(query_index "$GUID_LEROY")

# Check Duplicates
TOTAL_ENTRIES=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$GUID_DUPONT','$GUID_MARTIN','$GUID_BERNARD','$GUID_LEROY','$GUID_MOREAU')" 2>/dev/null)
DISTINCT_GUIDS=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(DISTINCT FchGnrl_IDDos) FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$GUID_DUPONT','$GUID_MARTIN','$GUID_BERNARD','$GUID_LEROY','$GUID_MOREAU')" 2>/dev/null)

HAS_DUPLICATES="false"
if [ "$TOTAL_ENTRIES" -ne "$DISTINCT_GUIDS" ]; then
    HAS_DUPLICATES="true"
fi

# --- REPORT FILE CHECKS ---
REPORT_FILE="/home/ga/orphan_repair_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CONTENT=""
REPORT_HAS_COUNT="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE")
    # Read content (escape for JSON)
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 1000 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' | sed 's/^"//;s/"$//')
    
    # Check if report mentions the count "3"
    if grep -qE "(^|\s)3(\s|$| records| patients)" "$REPORT_FILE"; then
        REPORT_HAS_COUNT="true"
    fi
fi

# --- FINAL SCREENSHOT ---
take_screenshot /tmp/task_final.png

# --- GENERATE JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_index_count": $INITIAL_INDEX_COUNT,
    "dupont_state": $DUPONT_STATE,
    "bernard_state": $BERNARD_STATE,
    "moreau_state": $MOREAU_STATE,
    "martin_state": $MARTIN_STATE,
    "leroy_state": $LEROY_STATE,
    "has_duplicates": $HAS_DUPLICATES,
    "total_entries": $TOTAL_ENTRIES,
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "has_summary_count": $REPORT_HAS_COUNT,
        "content_preview": "$REPORT_CONTENT"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="