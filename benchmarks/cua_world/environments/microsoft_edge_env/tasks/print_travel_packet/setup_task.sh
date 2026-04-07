#!/bin/bash
# setup_task.sh - Pre-task hook for print_travel_packet
# Sets up directory structure, installs dependencies, and prepares Edge.

set -e

echo "=== Setting up Print Travel Packet Task ==="

# 1. Install dependencies for verification (poppler-utils for pdftotext)
# We do this in setup to ensure export_result.sh runs smoothly
if ! command -v pdftotext &> /dev/null; then
    echo "Installing poppler-utils..."
    apt-get update -qq && apt-get install -yqq poppler-utils
fi

# 2. Prepare output directory
OUTPUT_DIR="/home/ga/Documents/TravelPacket"
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing directory: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# 3. Kill existing Edge instances
echo "Killing existing Edge instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# 4. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Clear history/downloads (optional, but good for clean history verification)
# We won't delete the DB files to avoid corruption, but we'll record the current max ID if needed.
# For simplicity, we'll just query timestamps > start_time in verification.

# 6. Launch Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# 7. Wait for Edge
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 8. Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="