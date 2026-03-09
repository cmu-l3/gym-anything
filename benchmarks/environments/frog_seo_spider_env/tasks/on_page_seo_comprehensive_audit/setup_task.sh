#!/bin/bash
# Setup script for On-Page SEO Comprehensive Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up On-Page SEO Comprehensive Audit Task ==="

kill_screamingfrog ga
sleep 1

echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Window not detected"
fi

sleep 5

eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

sleep 5

wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== On-Page SEO Comprehensive Audit Setup Complete ==="
echo ""
echo "TASK: Comprehensive on-page SEO audit of https://books.toscrape.com/"
echo "Required: Crawl ≥100 pages"
echo "Required output 1: Page titles CSV in ~/Documents/SEO/exports/"
echo "Required output 2: Meta descriptions CSV in ~/Documents/SEO/exports/"
echo "Required output 3: H1 tags CSV in ~/Documents/SEO/exports/"
echo "Required output 4: Audit summary at ~/Documents/SEO/reports/on_page_audit.txt"
