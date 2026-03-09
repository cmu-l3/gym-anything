#!/bin/bash
# Setup script for JS Rendering Content Gap Audit
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up JS Rendering Content Gap Audit ==="

# 1. Kill any existing instances
kill_screamingfrog ga
sleep 1

# 2. Record task start time for anti-gaming (file modification checks)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clean up previous artifacts
echo "Clearing previous data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"

# Clear SF cache/state to ensure rendering settings are reset or user has to set them
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
fi

# Ensure output directories exist
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/

# Remove old results
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/js_rendering_report.txt 2>/dev/null || true

# 4. Launch Screaming Frog
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

# Handle EULA if it appears
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for UI ready
echo "Waiting for Screaming Frog to initialize..."
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://quotes.toscrape.com/js/"
echo "Agent must ENABLE JavaScript rendering to pass this task."