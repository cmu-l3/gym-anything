#!/bin/bash
# Setup script for Pre-Migration Technical SEO Baseline task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pre-Migration Technical Baseline Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Prepare directories and clean stale outputs BEFORE recording timestamp
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Delete any pre-existing files that could cause false positives
rm -f "$EXPORT_DIR"/baseline_*.csv 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/migration_baseline_report.txt 2>/dev/null || true

# Record task start time AFTER cleaning (anti-gaming pattern)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# Clear Screaming Frog caches for clean crawl state
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if it appears
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for Screaming Frog to be fully loaded
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

sleep 5

# Focus the main window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Pre-Migration Technical Baseline Setup Complete ==="
echo ""
echo "TASK: Comprehensive pre-migration SEO baseline of https://books.toscrape.com/"
echo "Required CSV exports to ~/Documents/SEO/exports/:"
echo "  - baseline_internal_html.csv (Internal tab, filtered to HTML)"
echo "  - baseline_page_titles.csv (Page Titles tab)"
echo "  - baseline_meta_descriptions.csv (Meta Description tab)"
echo "  - baseline_images.csv (Images tab)"
echo "  - baseline_all_inlinks.csv (Bulk Export > Links > All Inlinks)"
echo "Required report: ~/Documents/SEO/reports/migration_baseline_report.txt"
