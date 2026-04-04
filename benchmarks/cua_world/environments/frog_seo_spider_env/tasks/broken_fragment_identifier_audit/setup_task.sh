#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Broken Fragment Identifier Audit Task ==="

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

# Ensure export directory exists and is empty of CSVs to start
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
# We don't delete everything, just record the state, but deleting makes verification cleaner for the agent
# Let's just record the initial state to be safe against pre-existing files
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null > /tmp/initial_csv_list.txt || touch /tmp/initial_csv_list.txt

# Record task start time for file modification tracking
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

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
wait_for_sf_ready 60

# Focus window
echo "Focusing Screaming Frog window..."
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "1. Enable 'Crawl Fragment Identifiers' in Configuration > Spider > Advanced."
echo "2. Crawl https://crawler-test.com/"
echo "3. Export the list of broken bookmarks/fragments to ~/Documents/SEO/exports/"