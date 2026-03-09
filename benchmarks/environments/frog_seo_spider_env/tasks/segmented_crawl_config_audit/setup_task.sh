#!/bin/bash
# Setup script for Segmented Crawl Config Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Segmented Crawl Config Audit ==="

# 1. cleanup environment
kill_screamingfrog ga
sleep 1

# Record task start time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# Clear previous crawl data/config
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    # We want to clear spider.config to ensure no previous segments exist
    # But we want to keep the license/EULA acceptance if possible.
    # The safest way is to remove custom config files that store segments.
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true
    # Re-apply basic config from env setup if needed, or let SF create default
fi

# Ensure export directories exist and are empty of target files
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"

rm -f "$EXPORT_DIR"/segmented_crawl.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/segment_counts.txt 2>/dev/null || true

# 2. Launch Screaming Frog
echo "Launching Screaming Frog..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window not visible yet"
fi

# 3. Wait for initialization
echo "Waiting for UI to be ready..."
wait_for_sf_ready 60

# 4. Handle EULA if it appears
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "Accepting EULA..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window key Return" || true
    sleep 2
fi

# Focus main window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Required Segments: Travel, Mystery, Poetry"