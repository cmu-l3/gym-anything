#!/bin/bash
echo "=== Setting up post_acquisition_asset_integration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time.txt

# 1. Record initial counts
INITIAL_COMPANIES=$(snipeit_db_query "SELECT COUNT(*) FROM companies WHERE deleted_at IS NULL" | tr -d '[:space:]')
INITIAL_LOCATIONS=$(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE deleted_at IS NULL" | tr -d '[:space:]')
INITIAL_USERS=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL" | tr -d '[:space:]')
INITIAL_ASSETS=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')

echo "$INITIAL_COMPANIES" > /tmp/initial_companies.txt
echo "$INITIAL_LOCATIONS" > /tmp/initial_locations.txt
echo "$INITIAL_USERS" > /tmp/initial_users.txt
echo "$INITIAL_ASSETS" > /tmp/initial_assets.txt

# 2. Cleanup any potential pre-existing target data
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('NB-001', 'NB-002', 'NB-003', 'NB-004')"
snipeit_db_query "DELETE FROM users WHERE username IN ('rchen', 'mwebb', 'pkapoor')"
snipeit_db_query "DELETE FROM locations WHERE name LIKE '%Austin%'"
snipeit_db_query "DELETE FROM companies WHERE name IN ('TechVantage Solutions', 'NovaBridge Consulting')"

# 3. Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2

# Navigate to the Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="