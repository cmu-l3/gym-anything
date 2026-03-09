#!/bin/bash
# Setup script for Target Page Inlink Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Target Page Inlink Audit Task ==="

# 1. Kill any existing instances to ensure a fresh start
kill_screamingfrog ga
sleep 1

# 2. Clear previous crawl data (CRITICAL for valid testing)
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# 3. Prepare export directory and clear old files
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Remove any existing versions of the expected output file
rm -f "$EXPORT_DIR/attic_inlinks.csv" 2>/dev/null || true
# Also clean up any other CSVs to make verification cleaner
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

# 4. Record task start time for anti-gaming (file modification check)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 5. Launch Screaming Frog
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

# Handle EULA if it appears
echo "Checking for EULA..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for full initialization
echo "Waiting for Screaming Frog to ready..."
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: 'A Light in the Attic' product page"
echo "Goal: Export Inlinks (incoming links) for this specific page"