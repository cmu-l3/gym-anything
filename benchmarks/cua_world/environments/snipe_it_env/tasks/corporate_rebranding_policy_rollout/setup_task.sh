#!/bin/bash
echo "=== Setting up corporate_rebranding_policy_rollout task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset settings to default to ensure a clean starting state
echo "Resetting Snipe-IT settings to default baseline..."
snipeit_db_query "UPDATE settings SET site_name='Snipe-IT Asset Management', default_currency='USD', support_email=NULL, header_color=NULL WHERE id=1"

# 2. Reset category policies to default (no acceptance, no emails)
echo "Resetting category policy flags..."
snipeit_db_query "UPDATE categories SET require_acceptance=0, checkin_email=0"

# 3. Ensure target categories exist (they are seeded by default, but verifying)
CATEGORIES_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM categories WHERE name IN ('Laptops', 'Tablets', 'Desktops') AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$CATEGORIES_COUNT" -lt 3 ]; then
    echo "WARNING: Expected categories missing, re-creating..."
    snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, require_acceptance, checkin_email, created_at, updated_at) VALUES ('Laptops', 'asset', 0, 0, NOW(), NOW())"
    snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, require_acceptance, checkin_email, created_at, updated_at) VALUES ('Tablets', 'asset', 0, 0, NOW(), NOW())"
    snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, require_acceptance, checkin_email, created_at, updated_at) VALUES ('Desktops', 'asset', 0, 0, NOW(), NOW())"
fi

# 4. Ensure Firefox is running and on Snipe-IT dashboard
ensure_firefox_snipeit
sleep 2

# 5. Navigate to the Snipe-IT dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== corporate_rebranding_policy_rollout task setup complete ==="