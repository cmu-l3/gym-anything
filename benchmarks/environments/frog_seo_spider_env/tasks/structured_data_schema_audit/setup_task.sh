#!/bin/bash
# Setup script for Structured Data Schema Audit task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Structured Data Schema Audit Task ==="

# 1. Kill any existing Screaming Frog instances to ensure fresh start
kill_screamingfrog ga
sleep 1

# 2. Record task start time for anti-gaming (file modification checks)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clear previous crawl data (cache/temp)
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    # Remove project files
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# 4. Prepare output directories and clear old files
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"

mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/

# Clear specific target files if they exist from previous runs
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/structured_data_audit.txt 2>/dev/null || true

# Record initial file counts
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_csv_count.txt

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for application to be ready
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

# Handle EULA if it appears
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# Stabilization
sleep 2

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Structured Data Audit Setup Complete ==="
echo "Target URL: https://books.toscrape.com/"
echo "Required: Structured Data extraction (JSON-LD, Microdata, RDFa)"
echo "Outputs needed:"
echo "  1. Structured Data CSV export -> ~/Documents/SEO/exports/"
echo "  2. Internal HTML CSV export -> ~/Documents/SEO/exports/"
echo "  3. Audit report -> ~/Documents/SEO/reports/structured_data_audit.txt"