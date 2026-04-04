#!/bin/bash
echo "=== Setting up TIH Zone Identification task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the Rail Manifest file on Desktop
cat > /home/ga/Desktop/rail_manifest.txt << EOF
RAIL SHIPMENT MANIFEST - INCOMING
Date: $(date +%F)
Security Level: HIGH

Please verify TIH Hazard Zones (A, B, C, D) for the following lading:

1. Phosgene (CAS 75-44-5)
2. Chlorine (CAS 7782-50-5)
3. Bromine (CAS 7726-95-6)
4. Allyl Alcohol (CAS 107-18-6)
5. Toluene (CAS 108-88-3)

Reference: 49 CFR 172.101 / ERG
EOF
chown ga:ga /home/ga/Desktop/rail_manifest.txt

# Remove previous output file if it exists
rm -f /home/ga/Documents/tih_security_audit.txt

# Ensure Firefox is running and valid
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga" 60
else
    # If running, ensure it's focused and on home page
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        maximize_firefox
        # Navigate to home
        su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/'"
    fi
fi

# Dismiss any startup dialogs just in case
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="