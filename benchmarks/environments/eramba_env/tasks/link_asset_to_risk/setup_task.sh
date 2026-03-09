#!/bin/bash
echo "=== Setting up link_asset_to_risk task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure the Risk exists
echo "Seeding Risk..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO risks (title, description, risk_score, created, modified, deleted) \
     SELECT 'Unencrypted Data at Rest', 'Risk of data exposure if storage media is stolen.', 5, NOW(), NOW(), 0 \
     WHERE NOT EXISTS (SELECT 1 FROM risks WHERE title='Unencrypted Data at Rest' AND deleted=0);" 2>/dev/null || true

# 2. Ensure the Asset exists
echo "Seeding Asset..."
# Note: 'assets' table structure varies by version, assuming standard fields. 
# If 'assets' table uses 'name' or 'title', we try to handle common schemas.
# We create a generic asset.
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO assets (name, description, created, modified, deleted) \
     SELECT 'Patient Records Database', 'Main SQL database for EHR.', NOW(), NOW(), 0 \
     WHERE NOT EXISTS (SELECT 1 FROM assets WHERE name='Patient Records Database' AND deleted=0);" 2>/dev/null || true

# 3. Clear any existing link between them to ensure the agent does the work
echo "Clearing existing links..."
# Get IDs
RISK_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT id FROM risks WHERE title='Unencrypted Data at Rest' LIMIT 1")
ASSET_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT id FROM assets WHERE name='Patient Records Database' LIMIT 1")

if [ -n "$RISK_ID" ] && [ -n "$ASSET_ID" ]; then
    # Assuming standard join table 'assets_risks'
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "DELETE FROM assets_risks WHERE risk_id=$RISK_ID AND asset_id=$ASSET_ID;" 2>/dev/null || true
fi

# 4. Verify Firefox is running and navigate to Risk module
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080/risk-management/index"
sleep 2

# 5. Take initial screenshot
take_screenshot /tmp/link_asset_to_risk_initial.png

echo "=== Setup complete ==="