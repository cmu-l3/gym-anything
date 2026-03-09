#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up datacenter_rack_elevation task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/rack_elevation.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/rack_elevation.png 2>/dev/null || true

# Create the hardware manifest file
cat > /home/ga/Desktop/rack_manifest.txt << 'EOF'
RACK INSTALLATION MANIFEST
==========================
Rack ID:  RK-NYC-042
Location: NYC-DC1, Row 7, Position 42
Capacity: 42U

UNIT ALLOCATION (Top to Bottom):
--------------------------------
U42      : [Network]  Cisco Catalyst 9300-48P (Hostname: sw-tor-a) - 1U
U41      : [Network]  Cisco Catalyst 9300-48P (Hostname: sw-tor-b) - 1U
U40      : [Passive]  48-port Cat6A Patch Panel - 1U
U39      : [Passive]  Horizontal Cable Manager - 1U
U38      : [Compute]  Dell PowerEdge R660 (Hostname: web01) - 1U
U37      : [Compute]  Dell PowerEdge R660 (Hostname: web02) - 1U
U36      : [Passive]  Horizontal Cable Manager - 1U
U34-U35  : [Compute]  Dell PowerEdge R760 (Hostname: app01) - 2U
U32-U33  : [Compute]  Dell PowerEdge R760 (Hostname: app02) - 2U
U31      : [Passive]  Horizontal Cable Manager - 1U
U29-U30  : [Database] Dell PowerEdge R760 (Hostname: db-primary) - 2U
U27-U28  : [Database] Dell PowerEdge R760 (Hostname: db-replica) - 2U
U24-U26  : [Power]    APC Smart-UPS SRT 3000VA (Hostname: ups-a) - 3U
U21-U23  : [Power]    APC Smart-UPS SRT 3000VA (Hostname: ups-b) - 3U
U01-U20  : [Empty]    Reserved for expansion
EOF

chown ga:ga /home/ga/Desktop/rack_manifest.txt
echo "Created manifest at /home/ga/Desktop/rack_manifest.txt"

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_rack.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/rack_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="