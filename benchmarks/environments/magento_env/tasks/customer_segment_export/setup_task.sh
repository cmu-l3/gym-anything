#!/bin/bash
# Setup script for Customer Segment Export task

echo "=== Setting up Customer Segment Export Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check login state and log in if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Seed specific test data (Wholesale vs Retail customers)
echo "Seeding customer data..."

# Get ID for Wholesale group (usually 2) and General group (usually 1)
WHOLESALE_ID=$(magento_query "SELECT customer_group_id FROM customer_group WHERE customer_group_code='Wholesale' LIMIT 1" 2>/dev/null | tail -1)
GENERAL_ID=$(magento_query "SELECT customer_group_id FROM customer_group WHERE customer_group_code='General' LIMIT 1" 2>/dev/null | tail -1)

# Fallback defaults if query fails
WHOLESALE_ID=${WHOLESALE_ID:-2}
GENERAL_ID=${GENERAL_ID:-1}

echo "Group IDs: Wholesale=$WHOLESALE_ID, General=$GENERAL_ID"

# Python script to insert customers via API or direct SQL if API fails
# Using direct SQL for speed/reliability in setup script
# Note: Password hash for "Password123" (approximate, for testing)
PASS_HASH="sha256:1000:ios8...:..."

# Clear existing test customers to ensure clean state
magento_query "DELETE FROM customer_entity WHERE email LIKE 'wholesale%@example.com' OR email LIKE 'retail%@example.com'" 2>/dev/null

# Create 3 Wholesale customers
for i in {1..3}; do
    EMAIL="wholesale${i}@example.com"
    magento_query "INSERT INTO customer_entity (group_id, store_id, website_id, created_at, email, firstname, lastname, is_active) VALUES ($WHOLESALE_ID, 1, 1, NOW(), '$EMAIL', 'Wholesale', 'User${i}', 1)" 2>/dev/null
done

# Create 3 Retail customers
for i in {1..3}; do
    EMAIL="retail${i}@example.com"
    magento_query "INSERT INTO customer_entity (group_id, store_id, website_id, created_at, email, firstname, lastname, is_active) VALUES ($GENERAL_ID, 1, 1, NOW(), '$EMAIL', 'Retail', 'User${i}', 1)" 2>/dev/null
done

# Verify seeding
COUNT_W=$(magento_query "SELECT COUNT(*) FROM customer_entity WHERE email LIKE 'wholesale%'" 2>/dev/null | tail -1)
COUNT_R=$(magento_query "SELECT COUNT(*) FROM customer_entity WHERE email LIKE 'retail%'" 2>/dev/null | tail -1)
echo "Seeded: $COUNT_W wholesale, $COUNT_R retail customers"

# Clean up any previous attempts
rm -f /home/ga/Documents/wholesale_leads.csv 2>/dev/null

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="