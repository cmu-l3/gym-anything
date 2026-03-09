#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Find Broken Links Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# CRITICAL: Clear any previous crawl data to ensure fresh start state
# This prevents false positives from cached/checkpointed crawl results
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
    echo "Cleared Screaming Frog cache and temp files"
fi

# Clear any previous export files that might match our criteria
rm -f /tmp/exported_crawl_report.csv 2>/dev/null || true
rm -f /tmp/broken_links_export.csv 2>/dev/null || true

# Note: This task uses a real public website (https://crawler-test.com/links/broken_links)
# specifically designed for testing broken link detection - no local server needed

# Record initial state
echo "Recording initial state..."
echo "$(date -Iseconds)" > /tmp/task_start_time

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for Screaming Frog to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if it appears (first-run dialog)
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for application to be FULLY ready (not just window visible)
echo "Waiting for Screaming Frog to fully initialize..."
echo "[$(date -Iseconds)] Starting wait_for_sf_ready..." >> /tmp/setup_timing.log
wait_for_sf_ready 60
echo "[$(date -Iseconds)] wait_for_sf_ready completed" >> /tmp/setup_timing.log

# Additional stabilization time after app reports ready
sleep 5
echo "[$(date -Iseconds)] Post-ready stabilization complete" >> /tmp/setup_timing.log

# Focus window
echo "Focusing Screaming Frog window..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused window: $wid"
fi

sleep 2

echo "=== Find Broken Links Task Setup Complete ==="
echo ""
echo "Instructions:"
echo "  1. Enter 'https://crawler-test.com/links/broken_links' in the URL bar and click Start"
echo "  2. Wait for the crawl to complete"
echo "  3. Click on the 'Response Codes' tab in the main panel"
echo "  4. Look for rows with Status Code 404 (Client Error 4xx filter)"
echo ""
echo "Target URL: https://crawler-test.com/links/broken_links"
echo "Note: This is a real public website with intentional broken links for testing"
echo "Expected: Find 404 errors on this broken links test page"
