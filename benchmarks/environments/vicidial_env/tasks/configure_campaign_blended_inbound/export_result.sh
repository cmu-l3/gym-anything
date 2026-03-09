#!/bin/bash
echo "=== Exporting task results ==="

# Source utils
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Final State
CAMP_ID="SENATE"
INGROUP_ID="SENATE_CB"

echo "Querying Vicidial database..."

# Check 1: Is Blended Mode Enabled? (allow_closers = 'Y')
ALLOW_CLOSERS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT allow_closers FROM vicidial_campaigns WHERE campaign_id='$CAMP_ID';" 2>/dev/null || echo "")

# Check 2: Is Linkage Created?
LINKAGE_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_campaign_ingroups WHERE campaign_id='$CAMP_ID' AND group_id='$INGROUP_ID';" 2>/dev/null || echo "0")

# Check 3: App running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "campaign_id": "$CAMP_ID",
    "ingroup_id": "$INGROUP_ID",
    "allow_closers_value": "$ALLOW_CLOSERS",
    "linkage_count": $LINKAGE_COUNT,
    "app_running": $APP_RUNNING,
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="