#!/bin/bash
# residential_plumbing_schematic setup
set -u

echo "=== Setting up Plumbing Schematic Task ==="

# 1. Generate the specification file
cat > /home/ga/Desktop/plumbing_specs.txt << 'EOF'
PROJECT: Miller Residence Plumbing Renovation
DATE: 2024-05-15
TYPE: Water Supply Schematic (Rough-in)

INSTRUCTIONS:
Create a schematic diagram showing the Hot and Cold water supply lines for the following fixtures.
Use BLUE lines for Cold water and RED lines for Hot water.

FIXTURE LIST:
1.  City Water Main (Source)
2.  Water Meter
3.  Water Heater (Tankless)
4.  Kitchen Sink
5.  Dishwasher
6.  Master Bath Sink (Double Vanity - treat as one block)
7.  Master Bath Shower
8.  Master Bath Toilet
9.  Guest Bath Sink
10. Guest Bath Toilet
11. Washing Machine

LOGIC REQUIREMENTS:
- Cold Water Main -> Meter -> Heater & All Cold Taps
- Heater Outlet -> All Hot Taps
- Toilets: Cold Water ONLY
- Dishwasher/Washer: Hot and Cold supply (or as per standard residential hookup)
EOF

chown ga:ga /home/ga/Desktop/plumbing_specs.txt
chmod 644 /home/ga/Desktop/plumbing_specs.txt

# 2. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous runs
rm -f /home/ga/Desktop/plumbing_schematic.drawio
rm -f /home/ga/Desktop/plumbing_schematic.png

# 4. Launch draw.io (Blank Canvas state)
# We use the drawio-launch helper or direct binary if available
echo "Launching draw.io..."
if command -v drawio &>/dev/null; then
    CMD="drawio"
elif [ -f /opt/drawio/drawio ]; then
    CMD="/opt/drawio/drawio"
else
    CMD="drawio" # hope for path
fi

# Launch with disable-update to avoid popups
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $CMD --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# 5. Wait for Window and Initialize
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss "Create New / Open Existing" dialog (Esc -> blank diagram)
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="