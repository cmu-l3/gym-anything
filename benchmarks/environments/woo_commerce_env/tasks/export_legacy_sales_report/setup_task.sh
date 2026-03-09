#!/bin/bash
set -e
echo "=== Setting up task: export_legacy_sales_report ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/last_month_sales.csv
# Clean downloads to prevent confusion
rm -f /home/ga/Downloads/sales_by_date*.csv

# Wait for database
echo "Waiting for database..."
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# =============================================================================
# Seed Backdated Orders (Real Data Simulation)
# =============================================================================
echo "Seeding backdated orders for 'Last Month'..."

# Calculate dates for "Last Month"
# Example: If today is 2023-03-07, Last Month is 2023-02-01 to 2023-02-28
# We use date arithmetic to get the YYYY-MM-DD range
CURRENT_EPOCH=$(date +%s)
# First day of last month
LAST_MONTH_START=$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-%d)
# Last day of last month
LAST_MONTH_END=$(date -d "$(date +%Y-%m-01) -1 day" +%Y-%m-%d)

echo "Generating orders between $LAST_MONTH_START and $LAST_MONTH_END"

# Get a valid product ID
PROD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' LIMIT 1")
if [ -z "$PROD_ID" ]; then
    echo "No products found. Creating one..."
    wp wc product create --name="Test Product" --regular_price="10" --user=admin --allow-root > /dev/null
    PROD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='product' AND post_status='publish' LIMIT 1")
fi

# Create 5 orders spread across the last month
for i in {1..5}; do
    # Pick a random offset
    DAYS_IN_MONTH=$(date -d "$LAST_MONTH_END" +%d)
    RAND_DAY=$((1 + RANDOM % DAYS_IN_MONTH))
    
    # Construct date: First of last month + random days (minus 1 to stay in month)
    ORDER_DATE=$(date -d "$LAST_MONTH_START + $((RAND_DAY - 1)) days 12:00:00" +"%Y-%m-%d %H:%M:%S")
    
    # Create order via WP-CLI (creates it at NOW)
    ORDER_ID=$(wp wc order create --user_id=1 --status=completed --allow-root --porcelain)
    
    # Add line item
    wp wc order line_item create $ORDER_ID --product_id=$PROD_ID --quantity=1 --allow-root > /dev/null
    
    # Update totals
    wp wc order update $ORDER_ID --allow-root > /dev/null
    
    # BACKDATE the order via SQL
    wc_query "UPDATE wp_posts SET post_date='$ORDER_DATE', post_date_gmt='$ORDER_DATE' WHERE ID=$ORDER_ID"
    wc_query "UPDATE wp_postmeta SET meta_value='$ORDER_DATE' WHERE post_id=$ORDER_ID AND meta_key='_completed_date'"
    wc_query "UPDATE wp_postmeta SET meta_value='$ORDER_DATE' WHERE post_id=$ORDER_ID AND meta_key='_paid_date'"
    
    echo "Created Order #$ORDER_ID backdated to $ORDER_DATE"
done

# Clear WooCommerce transients to ensure reports refresh
wc_query "DELETE FROM wp_options WHERE option_name LIKE '_transient_wc_report_%'"
wc_query "DELETE FROM wp_options WHERE option_name LIKE '_transient_timeout_wc_report_%'"

# =============================================================================
# App Setup
# =============================================================================

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Navigate explicitly to the Dashboard to start fresh (agent must find Reports)
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/wp-admin/index.php"
DISPLAY=:1 xdotool key Return
sleep 3

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="