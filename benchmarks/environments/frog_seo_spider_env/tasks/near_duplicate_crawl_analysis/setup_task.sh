#!/bin/bash
# Setup script for Near Duplicate Crawl Analysis task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Near Duplicate Crawl Analysis Task ==="

# 1. Kill any existing instances to ensure fresh start
kill_screamingfrog ga
sleep 1

# 2. Clear previous data/config to ensure "Near Duplicates" is DISABLED by default
# This forces the agent to actually configure it.
echo "Clearing previous crawl data and configuration..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    # We remove the config file to reset preferences (like Near Duplicates checkbox)
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true
    # Restore a basic config if needed, or let SF create default
fi

# 3. Prepare directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/

# 4. Clean up any previous run artifacts
rm -f "$EXPORT_DIR"/near_duplicates.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/similarity_analysis.txt 2>/dev/null || true

# 5. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_epoch
echo "$(date -Iseconds)" > /tmp/task_start_time

# 6. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 7. Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# 8. Wait for window and full initialization
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

echo "Waiting for Screaming Frog UI to stabilize..."
wait_for_sf_ready 60

# 9. Focus the window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

# 10. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://crawler-test.com/"
echo "Agent must: Enable Near Duplicates (90%), Crawl, Run Analysis, Export."