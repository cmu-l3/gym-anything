#!/bin/bash
# Setup script for Cookie Inventory Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Cookie Inventory Audit Task ==="

# Kill any existing Screaming Frog instances to ensure fresh config state
kill_screamingfrog ga
sleep 1

# Record task start time for file modification tracking
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# CRITICAL: Clear previous crawl data and configuration
# We want to ensure 'Store Cookies' is disabled (default) so the agent MUST enable it
echo "Clearing previous crawl data and resetting config..."
SF_CONFIG_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_CONFIG_DIR" ]; then
    # Remove config file to reset preferences (including Store Cookies)
    rm -f "$SF_CONFIG_DIR"/spider.config 2>/dev/null || true
    
    # Re-create minimal config to suppress EULA/updates but KEEP default spider settings
    # Note: We do NOT set 'storeCookies=true' here, ensuring it defaults to false
    mkdir -p "$SF_CONFIG_DIR"
    cat > "$SF_CONFIG_DIR"/spider.config << 'CONFIGEOF'
checkForUpdates=false
sendCrashReports=false
sendUsageStats=false
eulaAccepted=true
CONFIGEOF
    chown ga:ga "$SF_CONFIG_DIR"/spider.config
    
    # Clear cache
    rm -rf "$SF_CONFIG_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_CONFIG_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_CONFIG_DIR"/*.seospider 2>/dev/null || true
    echo "Reset Screaming Frog configuration"
fi

# Prepare export and report directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear any previous target files
rm -f "$EXPORT_DIR"/cookie_inventory.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/cookie_summary.txt 2>/dev/null || true

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Ensure full initialization
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60
echo "[$(date -Iseconds)] SF ready" >> /tmp/setup_timing.log

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Cookie Inventory Audit Setup Complete ==="
echo ""
echo "TASK: Audit cookies on https://crawler-test.com/"
echo "1. Configure spider to Store Cookies (Advanced settings)"
echo "2. Crawl the site"
echo "3. Bulk Export all cookies to ~/Documents/SEO/exports/cookie_inventory.csv"
echo "4. Create summary at ~/Documents/SEO/reports/cookie_summary.txt"