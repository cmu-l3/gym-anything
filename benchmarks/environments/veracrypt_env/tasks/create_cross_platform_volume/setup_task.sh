#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Cross-Platform Volume Task ==="

# 1. Clean up artifacts from previous runs
rm -f /home/ga/Volumes/dailies_transfer.hc 2>/dev/null || true
rm -f /home/ga/Documents/production_manifest.csv 2>/dev/null || true

# 2. Create the realistic source data (Manifest CSV)
cat > /home/ga/Documents/production_manifest.csv << EOF
Scene,Take,Duration,FileSize,Checksum,Notes
101,1,00:02:14,4.2GB,a1b2c3d4,"Good take, focus sharp"
101,2,00:03:05,5.8GB,e5f6g7h8,"Sound issue at 01:10"
102,1,00:01:45,3.1GB,i9j0k1l2,"Cloud cover changed lighting"
102,2,00:01:50,3.2GB,m3n4o5p6,"Best take for Scene 102"
INT_OFFICE,1,00:05:12,9.4GB,q7r8s9t0,"Long master shot"
EOF
chown ga:ga /home/ga/Documents/production_manifest.csv
chmod 644 /home/ga/Documents/production_manifest.csv

# 3. Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# 4. Wait for and focus window
if wait_for_window "VeraCrypt" 15; then
    wid=$(get_veracrypt_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Ensure it's not minimized
        DISPLAY=:1 wmctrl -i -r "$wid" -b remove,hidden,shaded 2>/dev/null || true
    fi
else
    echo "WARNING: VeraCrypt window not found"
fi

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="