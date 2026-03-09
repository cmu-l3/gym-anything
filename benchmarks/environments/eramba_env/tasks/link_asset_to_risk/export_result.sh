#!/bin/bash
echo "=== Exporting link_asset_to_risk results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Get IDs for verification
RISK_TITLE="Unencrypted Data at Rest"
ASSET_NAME="Patient Records Database"
REQUIRED_TEXT="Primary impact target is the Patient Records Database containing ePHI"

# 1. Query Database for Link
# We check the join table 'assets_risks'
LINK_EXISTS="false"
RISK_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT id FROM risks WHERE title='$RISK_TITLE' AND deleted=0 LIMIT 1")
ASSET_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT id FROM assets WHERE name='$ASSET_NAME' AND deleted=0 LIMIT 1")

if [ -n "$RISK_ID" ] && [ -n "$ASSET_ID" ]; then
    LINK_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
        "SELECT COUNT(*) FROM assets_risks WHERE risk_id=$RISK_ID AND asset_id=$ASSET_ID" 2>/dev/null || echo "0")
    
    if [ "$LINK_COUNT" -gt "0" ]; then
        LINK_EXISTS="true"
    fi
fi

# 2. Query Database for Text Update
TEXT_UPDATED="false"
# Check description field
CURRENT_DESC=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT description FROM risks WHERE id=$RISK_ID" 2>/dev/null || echo "")

if [[ "$CURRENT_DESC" == *"$REQUIRED_TEXT"* ]]; then
    TEXT_UPDATED="true"
fi

# 3. Check Modification Timestamp
MODIFIED_RECENTLY="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RISK_MODIFIED_TS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT UNIX_TIMESTAMP(modified) FROM risks WHERE id=$RISK_ID" 2>/dev/null || echo "0")

if [ "$RISK_MODIFIED_TS" -gt "$TASK_START" ]; then
    MODIFIED_RECENTLY="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/link_asset_to_risk_final.png

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "link_exists": $LINK_EXISTS,
    "text_updated": $TEXT_UPDATED,
    "risk_modified_recently": $MODIFIED_RECENTLY,
    "risk_id": "$RISK_ID",
    "asset_id": "$ASSET_ID",
    "screenshot_path": "/tmp/link_asset_to_risk_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="