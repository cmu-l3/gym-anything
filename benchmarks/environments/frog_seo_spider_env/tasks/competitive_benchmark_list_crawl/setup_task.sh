#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Competitive Benchmark List Crawl Task ==="

# Kill any existing Screaming Frog instances to ensure clean state
kill_screamingfrog ga
sleep 1

# Record task start time for anti-gaming (file modification checks)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# Clean up previous task artifacts
echo "Cleaning workspace..."
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
SF_CONFIG_DIR="/home/ga/.ScreamingFrogSEOSpider"

mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga "/home/ga/Documents/SEO"

# Remove specific target files if they exist
rm -f "$EXPORT_DIR/competitive_benchmark.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/competitive_report.txt" 2>/dev/null || true

# Clear Screaming Frog cache/state to ensure fresh session
if [ -d "$SF_CONFIG_DIR" ]; then
    rm -rf "$SF_CONFIG_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_CONFIG_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_CONFIG_DIR"/*.seospider 2>/dev/null || true
    # We do not delete spider.config to preserve license/settings, but we clear recent crawls
    rm -f "$SF_CONFIG_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# Handle EULA dialog if it appears (common on first run in fresh env)
echo "Checking for EULA dialog..."
sleep 5
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for application to be fully ready
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# Ensure window is focused and maximized
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "Environment ready for List Mode crawl."