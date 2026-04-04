#!/bin/bash
set -e

echo "=== Exporting HIPAA Campaign Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the Vicidial Database for the campaign configuration
# We use docker exec to run the query inside the container
echo "Querying Vicidial database..."

# Helper to run MySQL query and return JSON-like value or simple string
db_query() {
    local query="$1"
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$query" 2>/dev/null
}

CAMPAIGN_ID="HIPAA_SEC"

# Check if row exists
EXISTS=$(db_query "SELECT COUNT(*) FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")

if [ "$EXISTS" -eq "1" ]; then
    CAMPAIGN_EXISTS="true"
    
    # Fetch specific fields
    # We select them individually to ensure clean formatting
    ACTIVE=$(db_query "SELECT active FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    CALLERID=$(db_query "SELECT campaign_callerid FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    DISPLAY_LEAD=$(db_query "SELECT agent_display_lead_number FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    NO_ALTER_PHONE=$(db_query "SELECT disable_alter_custphone FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    NO_ALTER_DATA=$(db_query "SELECT disable_alter_custdata FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    MANUAL_DIAL=$(db_query "SELECT manual_dial_override FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    LEAD_SEARCH=$(db_query "SELECT agent_lead_search FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    QUEUE_VIEW=$(db_query "SELECT view_calls_in_queue FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    ENTRY_DATE=$(db_query "SELECT campaign_calldate FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")
    
    # Convert MySQL datetime to timestamp for anti-gaming check
    if [ -n "$ENTRY_DATE" ]; then
        ENTRY_TIMESTAMP=$(date -d "$ENTRY_DATE" +%s 2>/dev/null || echo "0")
    else
        ENTRY_TIMESTAMP="0"
    fi
else
    CAMPAIGN_EXISTS="false"
    ACTIVE=""
    CALLERID=""
    DISPLAY_LEAD=""
    NO_ALTER_PHONE=""
    NO_ALTER_DATA=""
    MANUAL_DIAL=""
    LEAD_SEARCH=""
    QUEUE_VIEW=""
    ENTRY_TIMESTAMP="0"
fi

# 4. Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_exists": $CAMPAIGN_EXISTS,
    "creation_timestamp": $ENTRY_TIMESTAMP,
    "config": {
        "active": "$ACTIVE",
        "campaign_callerid": "$CALLERID",
        "agent_display_lead_number": "$DISPLAY_LEAD",
        "disable_alter_custphone": "$NO_ALTER_PHONE",
        "disable_alter_custdata": "$NO_ALTER_DATA",
        "manual_dial_override": "$MANUAL_DIAL",
        "agent_lead_search": "$LEAD_SEARCH",
        "view_calls_in_queue": "$QUEUE_VIEW"
    }
}
EOF

# 5. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="