#!/bin/bash
echo "=== Setting up license_compliance_reconciliation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Record baseline state of all licenses
# ---------------------------------------------------------------
echo "  Recording baseline license state..."

# Get MS365 license data
MS365_DATA=$(snipeit_db_query "SELECT id, name, seats, purchase_cost, expiration_date, order_number FROM licenses WHERE name LIKE '%Microsoft 365%' AND deleted_at IS NULL LIMIT 1")
MS365_ID=$(echo "$MS365_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
MS365_SEATS=$(echo "$MS365_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
MS365_COST=$(echo "$MS365_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
echo "  MS365: id=$MS365_ID seats=$MS365_SEATS cost=$MS365_COST"
echo "$MS365_ID" > /tmp/license_ms365_id.txt
echo "$MS365_SEATS" > /tmp/license_ms365_seats.txt
echo "$MS365_COST" > /tmp/license_ms365_cost.txt

# Get Adobe CC license data
ADOBE_DATA=$(snipeit_db_query "SELECT id, name, seats, purchase_cost, expiration_date, order_number FROM licenses WHERE name LIKE '%Adobe Creative Cloud%' AND deleted_at IS NULL LIMIT 1")
ADOBE_ID=$(echo "$ADOBE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
ADOBE_SEATS=$(echo "$ADOBE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
ADOBE_COST=$(echo "$ADOBE_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
echo "  Adobe CC: id=$ADOBE_ID seats=$ADOBE_SEATS cost=$ADOBE_COST"
echo "$ADOBE_ID" > /tmp/license_adobe_id.txt
echo "$ADOBE_SEATS" > /tmp/license_adobe_seats.txt
echo "$ADOBE_COST" > /tmp/license_adobe_cost.txt

# Get Win11 license data
WIN11_DATA=$(snipeit_db_query "SELECT id, name, seats, purchase_cost, expiration_date, order_number FROM licenses WHERE name LIKE '%Windows 11%' AND deleted_at IS NULL LIMIT 1")
WIN11_ID=$(echo "$WIN11_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
WIN11_EXPIRY=$(echo "$WIN11_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
WIN11_ORDER=$(echo "$WIN11_DATA" | awk -F'\t' '{print $6}' | tr -d '[:space:]')
echo "  Win11: id=$WIN11_ID expiry=$WIN11_EXPIRY order=$WIN11_ORDER"
echo "$WIN11_ID" > /tmp/license_win11_id.txt
echo "$WIN11_EXPIRY" > /tmp/license_win11_expiry.txt
echo "$WIN11_ORDER" > /tmp/license_win11_order.txt

# Record total license count
TOTAL_LICENSES=$(snipeit_db_query "SELECT COUNT(*) FROM licenses WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$TOTAL_LICENSES" > /tmp/license_total_count.txt
echo "  Total licenses: $TOTAL_LICENSES"

# Record all license IDs for false-positive detection
snipeit_db_query "SELECT id, name, seats, purchase_cost, expiration_date, order_number FROM licenses WHERE deleted_at IS NULL ORDER BY id" > /tmp/license_all_baseline.txt

# Check if new license already exists
SLACK_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM licenses WHERE name LIKE '%Slack%' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$SLACK_EXISTS" -gt 0 ]; then
    echo "WARNING: Slack license already exists, removing"
    snipeit_db_query "DELETE FROM licenses WHERE name LIKE '%Slack%'"
fi

# Record timestamp
date +%s > /tmp/license_task_start.txt

# ---------------------------------------------------------------
# 2. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/license_initial.png

echo "=== license_compliance_reconciliation task setup complete ==="
echo "Task: Update 3 existing licenses and create 1 new license"
