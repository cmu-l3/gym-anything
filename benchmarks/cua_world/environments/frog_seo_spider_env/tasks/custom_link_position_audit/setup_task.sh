#!/bin/bash
# Setup script for Custom Link Position Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Link Position Audit ==="

# 1. Cleanup Environment
# Kill any running instances
kill_screamingfrog ga
sleep 1

# Clear previous configuration to ensure agent does the work
# We want them to set up the Link Positions, not inherit them
echo "Clearing previous Screaming Frog configuration..."
SF_CONFIG_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_CONFIG_DIR" ]; then
    # We preserve spider.config (license/memory settings) but remove user preferences
    # that might contain custom link positions from previous runs
    rm -f "$SF_CONFIG_DIR"/spider.preferences 2>/dev/null || true
    # Clear crawl data
    rm -rf "$SF_CONFIG_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_CONFIG_DIR"/tmp/* 2>/dev/null || true
fi

# Prepare output directories
mkdir -p "/home/ga/Documents/SEO/exports"
mkdir -p "/home/ga/Documents/SEO/reports"
chown -R ga:ga "/home/ga/Documents/SEO"

# Clean up any output files from previous runs
rm -f "/home/ga/Documents/SEO/exports/inlinks_by_position.csv" 2>/dev/null || true
rm -f "/home/ga/Documents/SEO/reports/link_distribution_report.txt" 2>/dev/null || true

# 2. Launch Application
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 60; then
    echo "WARNING: Screaming Frog window not detected"
fi

# Wait for full initialization
echo "Waiting for UI to stabilize..."
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 3. Record State
# Record task start time for verification
date +%s > /tmp/task_start_time
echo "$(date -Iseconds)" > /tmp/task_start_iso

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Required: Configure Custom Link Positions before crawling"