#!/bin/bash
# setup_task.sh - Pre-task hook for museum_qr_codes
set -e

echo "=== Setting up Museum QR Codes Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure utility for decoding QR codes is installed
# This is needed for the export_result.sh script to verify the generated images content
if ! command -v zbarimg &> /dev/null; then
    echo "Installing zbar-tools for QR verification..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq zbar-tools
fi

# Clean Desktop (remove previous run artifacts if any)
rm -f /home/ga/Desktop/eniac_qr.png
rm -f /home/ga/Desktop/hopper_qr.png
rm -f /home/ga/Desktop/transistor_qr.png
rm -f /home/ga/Desktop/qr_manifest.txt

# Clean Downloads (remove previous downloads to avoid confusion)
rm -f /home/ga/Downloads/qr_code*.png

# Ensure Edge is running
if ! pgrep -f "microsoft-edge" > /dev/null; then
    echo "Starting Microsoft Edge..."
    su - ga -c "DISPLAY=:1 microsoft-edge --no-first-run --no-default-browser-check &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="