#!/bin/bash
set -e

echo "=== Setting up Print Stylesheet Compliance Audit ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Install dependencies for PDF analysis (used in export_result.sh)
# We install inside the container so we can analyze the PDF before export
echo "Installing PDF analysis tools..."
pip3 install --break-system-packages pypdf || echo "Warning: Failed to install pypdf"

# 3. Clean up previous run artifacts
rm -f "/home/ga/Desktop/turing_print_audit.pdf"
rm -f "/tmp/task_result.json"

# 4. Kill any existing Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 5. Launch Microsoft Edge
# We launch it to a blank page or the target page? 
# Task description implies they navigate, but we can help by opening the browser.
# We'll open to about:blank to force them to navigate, adding a bit of friction 
# to ensure they check the URL, or we can open the target directly.
# Given it's a "Compliance Audit", navigating is part of the job, but opening the browser is helpful.
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank > /tmp/edge.log 2>&1 &"

# 6. Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window explicitly (redundancy)
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="