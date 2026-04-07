#!/bin/bash
# Setup script for Export Visitors API task

echo "=== Setting up Export Visitors API Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Clean up previous output file
OUTPUT_PATH="/home/ga/Documents/matomo_visitors_export.csv"
rm -f "$OUTPUT_PATH"
echo "Cleaned up previous export file at $OUTPUT_PATH"

# Ensure Matomo is installed
if ! matomo_is_installed; then
    echo "ERROR: Matomo not fully installed. Please complete installation first."
    # In a real scenario, we might force install here, but assuming env is ready
fi

# Ensure Initial Site exists (ID 1)
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ]; then
    echo "Creating Initial Site (ID 1)..."
    matomo_query "INSERT INTO matomo_site (idsite, name, main_url, ts_created, ecommerce, timezone, currency, type) VALUES (1, 'Initial Site', 'https://example.com', NOW(), 0, 'UTC', 'USD', 'website')" 2>/dev/null
fi

# Populate synthetic visitor data so the export is not empty
# This is CRITICAL for the CSV to have meaningful rows
echo "Populating synthetic visitor data..."
if [ -x /workspace/scripts/populate_visitor_data.sh ]; then
    /workspace/scripts/populate_visitor_data.sh > /tmp/data_pop.log 2>&1 || echo "Warning: Data population failed"
else
    echo "Warning: populate_visitor_data.sh not found"
fi

# Ensure admin user has an API token available or accessible
# (Matomo usually creates one by default or allows creating one)
# We won't pre-create one to force the agent to find/create it, 
# but we verify the user exists.
ADMIN_EXISTS=$(user_exists "admin")
if ! $ADMIN_EXISTS; then
    echo "Creating admin user..."
    # This relies on the matomo setup script having run, but just in case:
    PASS_HASH=$(docker exec matomo-app php -r "echo password_hash('Admin12345', PASSWORD_BCRYPT);")
    matomo_query "INSERT INTO matomo_user (login, password, email, superuser_access, date_registered) VALUES ('admin', '$PASS_HASH', 'admin@localhost.test', 1, NOW())" 2>/dev/null
fi

# Start Firefox on the API page to give a hint/starting point
echo "Starting Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Open to the API documentation page
API_DOCS_URL="http://localhost/index.php?module=API&action=listAllAPI"
su - ga -c "DISPLAY=:1 firefox '$API_DOCS_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="