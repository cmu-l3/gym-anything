#!/bin/bash
set -e
echo "=== Exporting configure_inbound_did_routing result ==="

# Define helper for MySQL queries inside Docker
vicidial_query() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$1" 2>/dev/null
}

# 1. Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Query In-Group Data
echo "Querying In-Group..."
IG_DATA=$(vicidial_query "SELECT group_id, group_name, active, next_agent_call, queue_priority, group_color FROM vicidial_inbound_groups WHERE group_id = 'GREENFIELD_SUP';")

# Parse In-Group data (tab separated)
IG_EXISTS="false"
IG_ID=""
IG_NAME=""
IG_ACTIVE=""
IG_NAC=""
IG_QP=""
IG_COLOR=""

if [ -n "$IG_DATA" ]; then
    IG_EXISTS="true"
    IG_ID=$(echo "$IG_DATA" | awk -F'\t' '{print $1}')
    IG_NAME=$(echo "$IG_DATA" | awk -F'\t' '{print $2}')
    IG_ACTIVE=$(echo "$IG_DATA" | awk -F'\t' '{print $3}')
    IG_NAC=$(echo "$IG_DATA" | awk -F'\t' '{print $4}')
    IG_QP=$(echo "$IG_DATA" | awk -F'\t' '{print $5}')
    IG_COLOR=$(echo "$IG_DATA" | awk -F'\t' '{print $6}')
fi

# 3. Query DID Data
echo "Querying DID..."
DID_DATA=$(vicidial_query "SELECT did_pattern, did_description, did_route, group_id, did_active FROM vicidial_inbound_dids WHERE did_pattern = '8005559247';")

# Parse DID data
DID_EXISTS="false"
DID_PATTERN=""
DID_DESC=""
DID_ROUTE=""
DID_GID=""
DID_ACTIVE=""

if [ -n "$DID_DATA" ]; then
    DID_EXISTS="true"
    DID_PATTERN=$(echo "$DID_DATA" | awk -F'\t' '{print $1}')
    DID_DESC=$(echo "$DID_DATA" | awk -F'\t' '{print $2}')
    DID_ROUTE=$(echo "$DID_DATA" | awk -F'\t' '{print $3}')
    DID_GID=$(echo "$DID_DATA" | awk -F'\t' '{print $4}')
    DID_ACTIVE=$(echo "$DID_DATA" | awk -F'\t' '{print $5}')
fi

# 4. Anti-Gaming: Check counts
INITIAL_IG_COUNT=$(cat /tmp/initial_ig_count.txt 2>/dev/null || echo "0")
CURRENT_IG_COUNT=$(vicidial_query "SELECT COUNT(*) FROM vicidial_inbound_groups;" | tr -d '[:space:]')
IG_DIFF=$((CURRENT_IG_COUNT - INITIAL_IG_COUNT))

INITIAL_DID_COUNT=$(cat /tmp/initial_did_count.txt 2>/dev/null || echo "0")
CURRENT_DID_COUNT=$(vicidial_query "SELECT COUNT(*) FROM vicidial_inbound_dids;" | tr -d '[:space:]')
DID_DIFF=$((CURRENT_DID_COUNT - INITIAL_DID_COUNT))

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ingroup": {
        "exists": $IG_EXISTS,
        "group_id": "$IG_ID",
        "group_name": "$IG_NAME",
        "active": "$IG_ACTIVE",
        "next_agent_call": "$IG_NAC",
        "queue_priority": "$IG_QP",
        "group_color": "$IG_COLOR"
    },
    "did": {
        "exists": $DID_EXISTS,
        "did_pattern": "$DID_PATTERN",
        "description": "$DID_DESC",
        "route": "$DID_ROUTE",
        "group_id": "$DID_GID",
        "active": "$DID_ACTIVE"
    },
    "stats": {
        "ingroup_count_diff": $IG_DIFF,
        "did_count_diff": $DID_DIFF
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="