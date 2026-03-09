#!/bin/bash
# Setup script for Custom Header Auth Bypass Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Header Auth Bypass Audit ==="

# 1. Clean environment
kill_screamingfrog ga
sleep 1

# Clear previous crawl data to ensure fresh state
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# Reset exports directory
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

# 2. Re-apply default config (clean slate for headers)
# We want to ensure NO custom headers are pre-set
sudo -u ga mkdir -p "$SF_DATA_DIR"
cat > "$SF_DATA_DIR/spider.config" << 'CONFIGEOF'
checkForUpdates=false
sendCrashReports=false
sendUsageStats=false
eulaAccepted=true
# Ensure no pre-existing http headers in config if possible, 
# though SF usually stores these in database/project files.
CONFIGEOF
chown -R ga:ga "$SF_DATA_DIR"

# 3. Record start time for anti-gaming
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 4. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# Wait for full initialization
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target URL: https://crawler-test.com/other/crawler_request_headers"
echo "Required Header: X-Audit-Token: SF-Verified-9988"