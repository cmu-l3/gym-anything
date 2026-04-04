#!/bin/bash
set -e
echo "=== Setting up System Health Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# =============================================================================
# COLLECT GROUND TRUTH
# =============================================================================
# We gather the actual system info programmatically to verify the agent's work.
# This data is hidden from the agent.

echo "Collecting system ground truth..."

# 1. FreeScout Version
# Try version.txt first, fallback to DB setting
GT_FS_VERSION=$(docker exec freescout-app cat /www/html/version.txt 2>/dev/null || echo "")
if [ -z "$GT_FS_VERSION" ]; then
    GT_FS_VERSION=$(fs_query "SELECT value FROM settings WHERE key = 'app_version'" 2>/dev/null || echo "Unknown")
fi

# 2. PHP Version
GT_PHP_VERSION=$(docker exec freescout-app php -r 'echo PHP_VERSION;' 2>/dev/null || echo "Unknown")

# 3. Database Version
GT_DB_VERSION=$(docker exec freescout-db mysql -u root -prootpass123 -N -e "SELECT VERSION()" 2>/dev/null || echo "Unknown")

# 4. Timezone
# FreeScout stores timezone in .env or app config. querying artisan is reliable.
GT_TIMEZONE=$(docker exec freescout-app php /www/html/artisan tinker --execute="echo config('app.timezone');" 2>/dev/null | grep -v "Psy Shell" | tail -n1 | tr -d '"' || echo "UTC")

# Save ground truth to a hidden location
mkdir -p /var/lib/freescout/ground_truth
cat > /var/lib/freescout/ground_truth/system_info.json << EOF
{
    "freescout_version": "$GT_FS_VERSION",
    "php_version": "$GT_PHP_VERSION",
    "database_version": "$GT_DB_VERSION",
    "timezone": "$GT_TIMEZONE"
}
EOF
chmod 600 /var/lib/freescout/ground_truth/system_info.json
echo "Ground truth saved."

# =============================================================================
# PREPARE ENVIRONMENT
# =============================================================================

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox

# Navigate to login page to ensure clean start
navigate_to_url "http://localhost:8080/login"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Ground Truth (Hidden):"
echo "  FS: $GT_FS_VERSION"
echo "  PHP: $GT_PHP_VERSION"
echo "  DB: $GT_DB_VERSION"
echo "  TZ: $GT_TIMEZONE"