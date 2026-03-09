#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: link_asset_to_policy ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure prerequisite data exists
# ---------------------------------------------------------------
echo "--- Ensuring prerequisite data ---"

# Create the "Information Security Policy" if it doesn't exist
# We use INSERT IGNORE or check existence to avoid duplicates
POLICY_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM security_policies WHERE title='Information Security Policy' AND deleted=0;" 2>/dev/null || echo "0")

if [ "$POLICY_COUNT" = "0" ]; then
    echo "  Creating 'Information Security Policy'..."
    eramba_db_query "INSERT INTO security_policies (title, description, published_date, next_review_date, version, use_attachments, permission, status, created, modified, deleted) VALUES ('Information Security Policy', 'Policy framework for protecting organizational information assets.', '2024-06-01', '2025-06-01', '2.1', 0, 0, 1, NOW(), NOW(), 0);" 2>/dev/null || true
fi

# Create the "Core Banking Application" business asset if it doesn't exist
ASSET_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM business_assets WHERE title='Core Banking Application' AND deleted=0;" 2>/dev/null || echo "0")

if [ "$ASSET_COUNT" = "0" ]; then
    echo "  Creating 'Core Banking Application' business asset..."
    # Note: business_unit_id=1 and asset_owner_id=1 are assumed to exist (seeded in environment setup)
    eramba_db_query "INSERT INTO business_assets (title, description, business_unit_id, asset_owner_id, created, modified, deleted) VALUES ('Core Banking Application', 'Primary banking transaction system.', 1, 1, NOW(), NOW(), 0);" 2>/dev/null || true
fi

# Retrieve IDs for setup logic
POLICY_ID=$(eramba_db_query "SELECT id FROM security_policies WHERE title='Information Security Policy' AND deleted=0 LIMIT 1;" 2>/dev/null)
ASSET_ID=$(eramba_db_query "SELECT id FROM business_assets WHERE title='Core Banking Application' AND deleted=0 LIMIT 1;" 2>/dev/null)

echo "  Target Policy ID: $POLICY_ID"
echo "  Target Asset ID: $ASSET_ID"

# Save IDs for export script
echo "$POLICY_ID" > /tmp/target_policy_id.txt
echo "$ASSET_ID" > /tmp/target_asset_id.txt

# ---------------------------------------------------------------
# 2. Ensure NO existing association
# ---------------------------------------------------------------
echo "--- Clearing existing associations ---"
# Check common Eramba naming conventions for HABTM tables
# Usually alphabetical: business_assets_security_policies
eramba_db_query "DELETE FROM business_assets_security_policies WHERE security_policy_id=${POLICY_ID} AND business_asset_id=${ASSET_ID};" 2>/dev/null || true
eramba_db_query "DELETE FROM security_policies_business_assets WHERE security_policy_id=${POLICY_ID} AND business_asset_id=${ASSET_ID};" 2>/dev/null || true

# ---------------------------------------------------------------
# 3. Setup Browser
# ---------------------------------------------------------------
echo "--- Setting up browser ---"
ensure_firefox_eramba "http://localhost:8080/security-policies/index"
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="