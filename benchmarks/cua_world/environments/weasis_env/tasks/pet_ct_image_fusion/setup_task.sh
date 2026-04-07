#!/bin/bash
echo "=== Setting up PET/CT Image Fusion task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

PET_CT_DIR="/home/ga/DICOM/pet_ct"
EXPORT_DIR="/home/ga/DICOM/exports"

# Create directories
mkdir -p "$PET_CT_DIR"
mkdir -p "$EXPORT_DIR"

# Ensure export dir is empty to avoid stale outputs
rm -f "$EXPORT_DIR"/* 2>/dev/null || true

# Download real PET/CT sample dataset if not present
if [ ! -f "$PET_CT_DIR/loaded.flag" ]; then
    echo "Downloading Rubo Medical clinical PET/CT sample dataset..."
    wget -q "https://www.rubomedical.com/dicom_files/dicom_viewer_0006.zip" -O /tmp/pet_ct.zip || true
    
    if [ -f /tmp/pet_ct.zip ]; then
        unzip -q -o /tmp/pet_ct.zip -d "$PET_CT_DIR/" || true
        rm -f /tmp/pet_ct.zip
        touch "$PET_CT_DIR/loaded.flag"
        echo "PET/CT data downloaded and extracted successfully."
    else
        echo "WARNING: Failed to download PET/CT sample dataset."
    fi
fi

# Set correct permissions so the agent user can read/write
chown -R ga:ga "/home/ga/DICOM"
chmod -R 777 "$EXPORT_DIR"

# Ensure no existing instances are running
pkill -f "weasis" 2>/dev/null || true
sleep 2

# Start Weasis explicitly as the ga user
echo "Starting Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "weasis"; then
        echo "Weasis window detected."
        break
    fi
    sleep 1
done

# Dismiss any first-run dialogs natively
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Maximize and focus the Weasis window for standard agent interaction
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Wait for UI stabilization before the initial screenshot
sleep 2

# Take screenshot of initial state as proof of clean setup
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="