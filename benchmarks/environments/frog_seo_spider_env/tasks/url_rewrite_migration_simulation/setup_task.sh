#!/bin/bash
# Setup script for URL Rewrite Migration Simulation task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up URL Rewrite Migration Simulation Task ==="

# 1. timestamp for anti-gaming
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 2. Cleanup previous state
echo "Cleaning up previous crawl data..."
kill_screamingfrog ga
sleep 1

SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true # Reset config to remove old rewrites
fi

# Ensure export directory exists and is empty of target files
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/migration_simulation.csv 2>/dev/null || true

# 3. Restore default config (re-run setup script function if needed, or just ensure clean slate)
# We specifically want to ensure no previous URL rewriting rules exist
# The deletion of spider.config above handles this, setup_screamingfrog.sh will recreate defaults on launch if missing? 
# Actually, let's manually recreate a basic clean config to be safe
mkdir -p "$SF_DATA_DIR"
cat > "$SF_DATA_DIR/spider.config" << 'CONFIGEOF'
checkForUpdates=false
sendCrashReports=false
sendUsageStats=false
exportDirectory=/home/ga/Documents/SEO/exports
storageMode=database
maxUriQueue=5000000
memoryLimit=4096
respectRobotsTxt=true
followRedirects=true
crawlCanonicals=true
CONFIGEOF
chown -R ga:ga "$SF_DATA_DIR"

# 4. Launch Application
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

echo "Waiting for Screaming Frog to initialize..."
wait_for_sf_ready 60

# 5. Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Goal: Rewrite '/catalogue/' to '/store/' and export CSV."