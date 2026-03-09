#!/bin/bash
set -e
echo "=== Setting up import_business_assets task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Create the CSV file with realistic data
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/inventory_import.csv <<EOF
Asset Name,Function,Owner
US-EAST-DB-01,Primary Customer Database - PostgreSQL Cluster,IT Ops
US-WEST-WEB-04,Frontend Webserver Pool A,IT Ops
EU-FR-API-02,Payment Gateway API Service (Legacy),FinTech Team
BAK-SRV-09,Offsite Backup Coordinator,Infra Team
DEV-BUILD-01,Jenkins CI/CD Build Agent,DevOps
EOF
chown ga:ga /home/ga/Documents/inventory_import.csv
echo "Created /home/ga/Documents/inventory_import.csv"

# 3. Record initial state (count of business assets)
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM business_assets WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_asset_count.txt
echo "Initial asset count: $INITIAL_COUNT"

# 4. Ensure Eramba is running and Firefox is open
# Navigate to Business Assets index to give a fair starting point, but not inside the import dialog
ensure_firefox_eramba "http://localhost:8080/business-assets/index"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="