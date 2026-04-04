#!/bin/bash
set -e
echo "=== Setting up task: chemical_storage_segregation ==="

# Source utilities if available, otherwise define minimal needed
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/storage_plan.csv
rm -f /home/ga/Desktop/shipment_manifest.txt

# 3. Create the Manifest File on Desktop
cat > /home/ga/Desktop/shipment_manifest.txt << 'EOF'
Hydrochloric Acid
Sodium Permanganate
Triethylamine
Methyl Ethyl Ketone
Potassium Hydroxide
EOF
chown ga:ga /home/ga/Desktop/shipment_manifest.txt
chmod 644 /home/ga/Desktop/shipment_manifest.txt

# 4. Ensure Firefox is running and valid
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote https://cameochemicals.noaa.gov/ > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window (Critical for VLM)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Try generic name if specific fails
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="