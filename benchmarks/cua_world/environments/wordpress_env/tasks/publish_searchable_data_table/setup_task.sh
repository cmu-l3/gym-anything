#!/bin/bash
# Setup script for publish_searchable_data_table task

echo "=== Setting up publish_searchable_data_table task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# ============================================================
# Prepare Real NASA Dataset (Meteorite Landings)
# ============================================================
echo "Preparing dataset..."
mkdir -p /home/ga/Documents
CSV_PATH="/home/ga/Documents/meteorite_landings.csv"

# Attempt to download real dataset from NASA Open Data API, limit to 101 lines (header + 100 rows)
curl -sL "https://data.nasa.gov/api/views/gh4g-9sfh/rows.csv" | head -n 101 > "$CSV_PATH"

# Verify if download was successful and contains expected data
if ! grep -q "Aachen" "$CSV_PATH"; then
    echo "Download failed or data mismatch, creating fallback real dataset..."
    # Fallback with exact real data to ensure the task can always be completed
    cat > "$CSV_PATH" << EOF
name,id,nametype,recclass,mass (g),fall,year,reclat,reclong,GeoLocation
Aachen,1,Valid,L5,21,Fell,1880,50.775000,6.083330,"(50.775, 6.08333)"
Aarhus,2,Valid,H6,720,Fell,1951,56.183330,10.233330,"(56.18333, 10.23333)"
Abee,6,Valid,EH4,107000,Fell,1952,54.216670,-113.000000,"(54.21667, -113.0)"
Acapulco,10,Valid,Acapulcoite,1914,Fell,1976,16.883330,-99.900000,"(16.88333, -99.9)"
Achiras,370,Valid,L6,780,Fell,1902,-33.166670,-64.950000,"(-33.16667, -64.95)"
Adhi Kot,379,Valid,EH4,4239,Fell,1919,32.100000,71.800000,"(32.1, 71.8)"
Adzhi-Bogdo (stone),390,Valid,LL3-6,910,Fell,1949,44.833330,95.166670,"(44.83333, 95.16667)"
Agen,392,Valid,H5,30000,Fell,1814,44.216670,0.466670,"(44.21667, 0.46667)"
Aguada,398,Valid,L6,1620,Fell,1930,-31.600000,-65.233330,"(-31.6, -65.23333)"
Aguila Blanca,417,Valid,L,1440,Fell,1920,-30.866670,-64.550000,"(-30.86667, -64.55)"
EOF
fi

# Set proper permissions so the agent can read it
chown ga:ga "$CSV_PATH"
chmod 644 "$CSV_PATH"

echo "Dataset prepared at $CSV_PATH"

# ============================================================
# Record Initial State
# ============================================================
# Ensure tablepress is not active initially
cd /var/www/html/wordpress
wp plugin deactivate tablepress --allow-root 2>/dev/null || true
wp plugin delete tablepress --allow-root 2>/dev/null || true

INITIAL_POST_COUNT=$(wp post list --post_type=post --post_status=publish --format=count --allow-root 2>/dev/null || echo "0")
echo "$INITIAL_POST_COUNT" > /tmp/initial_post_count.txt

# ============================================================
# Ensure Firefox is Running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/plugin-install.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="