#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Directory Tree Visualization Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Clear previous crawl data to ensure fresh start
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Prepare output directory and clean up old results
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga "/home/ga/Documents/SEO" 2>/dev/null || true

# Remove any existing output file to prevent false positives
rm -f "$REPORTS_DIR/site_tree.png" 2>/dev/null || true

# Record task start time for timestamp verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

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

# Handle EULA if needed
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for full initialization
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# Stabilization and focus
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: Generate Directory Tree Graph for https://books.toscrape.com/"
echo "Output: /home/ga/Documents/SEO/reports/site_tree.png"