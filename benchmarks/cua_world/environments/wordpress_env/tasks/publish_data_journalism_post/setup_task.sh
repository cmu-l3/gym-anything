#!/bin/bash
# Setup script for publish_data_journalism_post task (pre_task hook)

echo "=== Setting up publish_data_journalism_post task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s | sudo tee /tmp/task_start_timestamp > /dev/null
sudo chmod 666 /tmp/task_start_timestamp

# Create the real CSV data file from USGS (Simulated extraction)
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/earthquake_data.csv << 'EOF'
Location,Magnitude,Date,Depth_km
Kahramanmaras Turkey,7.8,2023-02-06,10.0
Al Haouz Morocco,6.8,2023-09-08,18.5
Herat Afghanistan,6.3,2023-10-07,14.0
Jajarkot Nepal,5.6,2023-11-03,32.6
Jishishan China,5.9,2023-12-18,10.0
EOF
chown ga:ga /home/ga/Documents/earthquake_data.csv
chmod 644 /home/ga/Documents/earthquake_data.csv

echo "Created earthquake_data.csv"

# Record initial post count
INITIAL_POST_COUNT=$(get_post_count "post" "publish")
echo "$INITIAL_POST_COUNT" | sudo tee /tmp/initial_post_count > /dev/null
sudo chmod 666 /tmp/initial_post_count
echo "Initial published post count: $INITIAL_POST_COUNT"

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."

if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox is not running! Starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window and maximize
echo "Focusing Firefox window..."
for i in {1..10}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Firefox window focused: $WID"
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="