#!/bin/bash
echo "=== Exporting link_asset_to_vendor results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for the Association
# We check if the row exists in assets_third_parties
echo "Querying database for association..."

# Create a temporary SQL script to output JSON-like structure
TEMP_SQL=$(mktemp /tmp/check_link.XXXXXX.sql)
cat > "$TEMP_SQL" << SQL_EOF
SELECT 
    COUNT(*) as link_count
FROM assets_third_parties atp
JOIN assets a ON atp.asset_id = a.id
JOIN third_parties tp ON atp.third_party_id = tp.id
WHERE a.name = 'HR Employee Portal' 
  AND tp.name = 'Workday Inc.';
SQL_EOF

LINK_COUNT=$(docker exec -i eramba-db mysql -u eramba -peramba_db_pass eramba -N < "$TEMP_SQL" 2>/dev/null || echo "0")
rm -f "$TEMP_SQL"

# 3. Check timestamps (if available in the join table, though often join tables don't have created fields)
# If assets_third_parties doesn't have 'created', we rely on 'modified' of the parent asset 
# or just the existence of the link since we cleared it at setup.
# Let's check if the asset was modified recently as a proxy if the link table is simple.
ASSET_MODIFIED_TS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT UNIX_TIMESTAMP(modified) FROM assets WHERE name='HR Employee Portal';" 2>/dev/null || echo "0")

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LINK_EXISTS="false"

if [ "$LINK_COUNT" -ge "1" ]; then
    LINK_EXISTS="true"
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "link_exists": $LINK_EXISTS,
    "link_count": $LINK_COUNT,
    "asset_modified_timestamp": $ASSET_MODIFIED_TS,
    "task_start_timestamp": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="