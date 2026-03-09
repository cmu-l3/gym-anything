#!/bin/bash
# Setup script for Image Alt Text Audit task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Image Alt Text Audit Task ==="

# 1. clean up environment
kill_screamingfrog ga
sleep 1

# Clear Screaming Frog cache to ensure a fresh crawl
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# 2. Prepare directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/

# Clear any previous task artifacts
rm -f "$EXPORT_DIR"/*image*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/image_audit_report.txt 2>/dev/null || true

# 3. Record start state
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
ls -1 "$EXPORT_DIR" > /tmp/initial_exports_list.txt 2>/dev/null || true

# 4. Launch Application
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for UI readiness
echo "Waiting for Screaming Frog to initialize..."
wait_for_sf_ready 60

# Maximize and focus
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Take initial evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Required Outputs:"
echo "  1. Image CSV export in ~/Documents/SEO/exports/ (filename must contain 'image')"
echo "  2. Audit report in ~/Documents/SEO/reports/image_audit_report.txt"