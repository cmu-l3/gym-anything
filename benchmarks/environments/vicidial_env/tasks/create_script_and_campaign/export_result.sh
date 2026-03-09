#!/bin/bash
echo "=== Exporting Create Script and Campaign results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Query Database for Script
echo "Querying Script..."
SCRIPT_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT script_id, script_name, script_text, active FROM vicidial_scripts WHERE script_id='SENATE_V1' LIMIT 1\G" | \
    awk -F': ' '
    /script_id/ {id=$2} 
    /script_name/ {name=$2} 
    /script_text/ {text=$2; for(i=3;i<=NF;i++) text=text" "$i} 
    /active/ {active=$2} 
    END {
        # Simple JSON construction (escaping quotes would be better, but this is a basic extraction)
        gsub(/"/, "\\\"", text);
        printf "{\"id\": \"%s\", \"name\": \"%s\", \"text\": \"%s\", \"active\": \"%s\"}", id, name, text, active
    }'
)

if [ -z "$SCRIPT_JSON" ] || [ "$SCRIPT_JSON" == '{"id": "", "name": "", "text": "", "active": ""}' ]; then
    SCRIPT_JSON="null"
fi

# Query Database for Campaign
echo "Querying Campaign..."
CAMPAIGN_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT campaign_id, campaign_name, active, campaign_script FROM vicidial_campaigns WHERE campaign_id='SENATE_OPS' LIMIT 1\G" | \
    awk -F': ' '
    /campaign_id/ {id=$2} 
    /campaign_name/ {name=$2} 
    /active/ {active=$2} 
    /campaign_script/ {script=$2} 
    END {
        printf "{\"id\": \"%s\", \"name\": \"%s\", \"active\": \"%s\", \"campaign_script\": \"%s\"}", id, name, active, script
    }'
)

if [ -z "$CAMPAIGN_JSON" ] || [ "$CAMPAIGN_JSON" == '{"id": "", "name": "", "active": "", "campaign_script": ""}' ]; then
    CAMPAIGN_JSON="null"
fi

# Initial counts for anti-gaming
INIT_SCRIPT=$(cat /tmp/initial_script_count.txt 2>/dev/null || echo "0")
INIT_CAMPAIGN=$(cat /tmp/initial_campaign_count.txt 2>/dev/null || echo "0")

# Construct full result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_script_count": $INIT_SCRIPT,
    "initial_campaign_count": $INIT_CAMPAIGN,
    "script_data": $SCRIPT_JSON,
    "campaign_data": $CAMPAIGN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="