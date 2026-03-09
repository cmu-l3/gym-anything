#!/bin/bash
set -e
echo "=== Setting up Antipodal Point Marking task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create Google Earth directories if they don't exist
mkdir -p /home/ga/.googleearth
mkdir -p /home/ga/.config/Google
chown -R ga:ga /home/ga/.googleearth
chown -R ga:ga /home/ga/.config/Google

# Backup existing myplaces.kml and record initial state
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
INITIAL_PLACEMARK_COUNT="0"

if [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/myplaces_backup.kml
    # Count existing placemarks
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if "Quito Antipode" already exists
    if grep -q "Quito Antipode" "$MYPLACES_FILE" 2>/dev/null; then
        echo "WARNING: 'Quito Antipode' placemark already exists, removing it"
        # Create a cleaned version without the existing placemark
        python3 << 'PYEOF'
import re
with open("/home/ga/.googleearth/myplaces.kml", "r") as f:
    content = f.read()
# Remove any existing Quito Antipode placemark
pattern = r'<Placemark[^>]*>.*?<name>Quito Antipode</name>.*?</Placemark>'
content = re.sub(pattern, '', content, flags=re.DOTALL | re.IGNORECASE)
with open("/home/ga/.googleearth/myplaces.kml", "w") as f:
    f.write(content)
PYEOF
        INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    fi
else
    # Create a minimal myplaces.kml if it doesn't exist
    cat > "$MYPLACES_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
    <name>My Places</name>
    <open>1</open>
</Document>
</kml>
EOF
    chown ga:ga "$MYPLACES_FILE"
    INITIAL_MTIME="0"
fi

echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "$INITIAL_MTIME" > /tmp/initial_myplaces_mtime.txt

# Save initial state as JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "initial_myplaces_mtime": ${INITIAL_MTIME:-0},
    "myplaces_existed": $([ -f /tmp/myplaces_backup.kml ] && echo "true" || echo "false")
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_antipodal.log 2>&1 &

# Wait for Google Earth window to appear (can take 10-30 seconds)
echo "Waiting for Google Earth Pro to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth Pro window not detected after 60 seconds"
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true

# Dismiss any startup dialogs or tips by pressing Escape
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Navigate to antipodal point and create placemark"
echo "============================================================"
echo ""
echo "Source: Quito, Ecuador (0.1807° S, 78.4678° W)"
echo "Target: Antipodal point (0.1807° N, 101.5322° E)"
echo "        This is in Sumatra, Indonesia"
echo ""
echo "Steps:"
echo "1. Calculate antipodal coordinates from Quito"
echo "2. Navigate to: 0.1807, 101.5322"
echo "3. Create placemark named: 'Quito Antipode'"
echo "4. Save to My Places"
echo "============================================================"