#!/bin/bash
set -e
echo "=== Setting up Create Restricted Coupon Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure 'Clothing' category exists
echo "Ensuring 'Clothing' category exists..."
# Check if exists
CAT_ID=$(wp wc product_cat list --search="Clothing" --format=json --user=admin --allow-root | jq -r '.[0].id // empty')

if [ -z "$CAT_ID" ]; then
    echo "Creating Clothing category..."
    wp wc product_cat create --name="Clothing" --user=admin --allow-root > /dev/null
    CAT_ID=$(wp wc product_cat list --search="Clothing" --format=json --user=admin --allow-root | jq -r '.[0].id')
fi
echo "Clothing Category ID: $CAT_ID"
echo "$CAT_ID" > /tmp/target_category_id.txt

# 2. Delete existing coupon if it exists (idempotency)
echo "Checking for existing 'CLOTHING-DEAL' coupon..."
EXISTING_ID=$(wp wc coupon list --search="CLOTHING-DEAL" --format=json --user=admin --allow-root | jq -r '.[0].id // empty')

if [ -n "$EXISTING_ID" ]; then
    echo "Deleting existing coupon ID: $EXISTING_ID"
    wp wc coupon delete "$EXISTING_ID" --force --user=admin --allow-root > /dev/null
fi

# 3. Ensure WordPress admin is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 4. Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="