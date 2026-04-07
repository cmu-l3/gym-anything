#!/bin/bash
# Setup script for Configure Data Retention task

echo "=== Setting up Configure Data Retention Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Matomo is installed
if ! matomo_is_installed; then
    echo "ERROR: Matomo installation wizard is still showing"
    echo "Please complete the Matomo installation first"
fi

# Reset PrivacyManager settings to defaults to ensure a clean start
# This ensures "Do Nothing" fails because defaults are different from target
echo "Resetting data retention settings to defaults..."
matomo_query "DELETE FROM matomo_option WHERE option_name LIKE 'PrivacyManager.%'" 2>/dev/null || true

# Insert default values (Disabled, 180/365 placeholders, all reports kept)
# Note: Matomo defaults usually have these disabled (0).
# We explicitly set them to ensure we know the starting state.
matomo_query "INSERT INTO matomo_option (option_name, option_value, autoload) VALUES 
    ('PrivacyManager.delete_logs_enable', '0', 1),
    ('PrivacyManager.delete_logs_older_than', '180', 1),
    ('PrivacyManager.delete_reports_enable', '0', 1),
    ('PrivacyManager.delete_reports_older_than', '365', 1),
    ('PrivacyManager.delete_reports_keep_basic_metrics', '1', 1),
    ('PrivacyManager.delete_reports_keep_day_reports', '1', 1),
    ('PrivacyManager.delete_reports_keep_week_reports', '1', 1),
    ('PrivacyManager.delete_reports_keep_month_reports', '1', 1),
    ('PrivacyManager.delete_reports_keep_year_reports', '1', 1),
    ('PrivacyManager.delete_reports_keep_segment_reports', '1', 1)
    ON DUPLICATE KEY UPDATE option_value=VALUES(option_value)" 2>/dev/null

# Record initial state for verification (Anti-gaming)
echo "Recording initial state..."
# Capture all PrivacyManager options
matomo_query "SELECT option_name, option_value FROM matomo_option WHERE option_name LIKE 'PrivacyManager.%'" > /tmp/initial_privacy_options.txt
echo "Initial state recorded."

# Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Ensure Firefox is running on Matomo
echo "Ensuring Firefox is running..."
MATOMO_URL="http://localhost/"

# Kill any existing Firefox instances for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$MATOMO_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Dismiss any Firefox first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

echo ""
echo "=== Configure Data Retention Task Setup Complete ==="
echo ""
echo "TASK: Configure Data Retention Settings"
echo "Login credentials: admin / Admin12345"
echo "Target: Log retention=180 days, Report retention=365 days, Delete Daily/Weekly reports"
echo ""