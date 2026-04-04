#!/bin/bash
# Setup script for Readability Content Quality Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Readability Audit Task ==="

# Kill any existing Screaming Frog instances to ensure fresh start
kill_screamingfrog ga
sleep 1

# Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# CRITICAL: Clear previous crawl data/config to ensure Readability is OFF by default
# This forces the agent to actually configure it
echo "Clearing previous crawl data and configuration..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    # Clear crawl data
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    
    # Reset spider.config to ensure default settings (Readability OFF)
    # We re-run the setup function from install scripts if needed, or just ensure config is clean
    # For this task, we want the default "spider.config" which usually has basic settings
    # The default setup_screamingfrog.sh creates a basic config.
    # We will verify it doesn't have "enableReadability=true" (imaginary flag, but ensuring defaults)
    echo "Resetting configuration..."
    # (The environment startup script handles the base config, we just ensure no persistent state)
fi

# Create required directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear any target files from previous runs
rm -f "$EXPORT_DIR/readability_audit.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/hardest_to_read.txt" 2>/dev/null || true

# Record initial export state
INITIAL_EXPORT_COUNT=$(ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_EXPORT_COUNT" > /tmp/initial_export_count

echo "Target URL: https://books.toscrape.com/"

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if present (first-run)
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for SF to fully initialize
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60
echo "[$(date -Iseconds)] wait_for_sf_ready completed" >> /tmp/setup_timing.log

# Additional stabilization
sleep 5

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Readability Audit Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "  1. Enable 'Readability' (Flesch Reading Ease) in Configuration"
echo "  2. Crawl https://books.toscrape.com/"
echo "  3. Export Content analysis to ~/Documents/SEO/exports/readability_audit.csv"
echo "  4. Create report at ~/Documents/SEO/reports/hardest_to_read.txt with the lowest scoring URL"