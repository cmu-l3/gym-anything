#!/bin/bash
# Setup script for Code Bloat Ratio Audit task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Code Bloat Ratio Audit Task ==="

# 1. Kill any existing instances to ensure fresh start
kill_screamingfrog ga
sleep 1

# 2. Clear previous data and artifacts
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# Create directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Remove specific target files if they exist
rm -f "$EXPORT_DIR/code_bloat_data.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/bloat_analysis.txt" 2>/dev/null || true

# 3. Record start timestamp for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 4. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 5. Wait for application to be ready
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# Wait for full initialization
echo "Waiting for Screaming Frog to initialize..."
wait_for_sf_ready 60

# 6. Set focus
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Goal: Export Text to Code Ratio data and write analysis report."