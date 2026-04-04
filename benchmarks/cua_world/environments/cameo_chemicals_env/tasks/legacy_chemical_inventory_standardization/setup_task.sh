#!/bin/bash
set -e
echo "=== Setting up task: Legacy Chemical Inventory Standardization ==="

# Source utilities if available, otherwise define basics
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/standardized_inventory.csv 2>/dev/null || true
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# 3. Create the input file for the agent
cat > /home/ga/Desktop/legacy_inventory_list.txt << EOF
Muriatic Acid
Caustic Soda
Wood Alcohol
MEK
Oil of Vitriol
Dry Ice
EOF
# Set permissions
chown ga:ga /home/ga/Desktop/legacy_inventory_list.txt

# 4. Ensure Firefox is running and clean
# Kill existing instances to ensure clean state
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote https://cameochemicals.noaa.gov/ > /tmp/firefox_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "CAMEO"; then
        echo "Firefox window found."
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "CAMEO" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "CAMEO" 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="