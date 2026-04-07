#!/bin/bash
# Setup script for Configure Global Defaults task

echo "=== Setting up Configure Global Defaults Task ==="
source /workspace/scripts/task_utils.sh

# Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# ── 1. Set known 'wrong' defaults (Baseline) ──────────────────────────────
# We enforce the starting state to ensure the task requires actual work.
# General Settings: UTC and USD
# Personal Settings: Today and Day

echo "Forcing baseline settings (UTC, USD, Today, Day)..."

# Helper to insert or update option
set_option() {
    local name="$1"
    local value="$2"
    # Check if exists
    local exists=$(matomo_query "SELECT count(*) FROM matomo_option WHERE option_name='$name'")
    if [ "$exists" -gt 0 ]; then
        matomo_query "UPDATE matomo_option SET option_value='$value' WHERE option_name='$name'"
    else
        matomo_query "INSERT INTO matomo_option (option_name, option_value, autoload) VALUES ('$name', '$value', 1)"
    fi
}

# Set General Settings
set_option "SitesManager_DefaultTimezone" "UTC"
set_option "SitesManager_DefaultCurrency" "USD"

# Set Personal Settings (for user 'admin')
# Note: Matomo stores these with variable naming conventions, we'll set common ones
set_option "UsersManager.userPreference.admin.defaultReport" "day"
set_option "UsersManager.userPreference.admin.defaultReportDate" "today"
# Also try legacy/alternative naming format just in case
set_option "UsersManager_userPreference_admin_defaultReport" "day"
set_option "UsersManager_userPreference_admin_defaultReportDate" "today"

echo "Baseline settings applied."

# ── 2. Record Baseline State ──────────────────────────────────────────────
# We capture the state we just set to verify against later (anti-gaming)
echo "Recording baseline state..."

get_option() {
    local name="$1"
    matomo_query "SELECT option_value FROM matomo_option WHERE option_name='$name'"
}

BASE_TZ=$(get_option "SitesManager_DefaultTimezone")
BASE_CURR=$(get_option "SitesManager_DefaultCurrency")
# Try both formats for preferences, take the one that returns a value
BASE_PERIOD=$(get_option "UsersManager.userPreference.admin.defaultReport")
[ -z "$BASE_PERIOD" ] && BASE_PERIOD=$(get_option "UsersManager_userPreference_admin_defaultReport")

BASE_DATE=$(get_option "UsersManager.userPreference.admin.defaultReportDate")
[ -z "$BASE_DATE" ] && BASE_DATE=$(get_option "UsersManager_userPreference_admin_defaultReportDate")

cat > /tmp/initial_defaults.json << EOF
{
    "timezone": "$BASE_TZ",
    "currency": "$BASE_CURR",
    "report_period": "$BASE_PERIOD",
    "report_date": "$BASE_DATE"
}
EOF

echo "Baseline recorded:"
cat /tmp/initial_defaults.json

# ── 3. Application Setup ──────────────────────────────────────────────────
# Ensure Firefox is running
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for window
if wait_for_window "firefox\|mozilla\|Matomo" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: Firefox window not detected"
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Configure Global Defaults Setup Complete ==="
echo "Instructions:"
echo "1. Change Default Timezone to 'Europe/Paris'"
echo "2. Change Default Currency to 'EUR'"
echo "3. Change Report Date default to 'Yesterday'"
echo "4. Change Report Period default to 'Week'"