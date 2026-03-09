#!/bin/bash
set -u

echo "=== Setting up hydraulic_forklift_circuit task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Create the specifications file
cat > /home/ga/Desktop/hydraulic_specs.txt << 'EOF'
HYDRAULIC CIRCUIT SPECIFICATIONS
Project: Series-X Forklift Lift System
Standard: ISO 1219 Symbols

COMPONENTS:
1. Power Unit:
   - Electric Motor (M)
   - Fixed Displacement Hydraulic Pump
   - Hydraulic Reservoir (Tank)

2. Control:
   - Pressure Relief Valve (Set to 2000 PSI) for system protection
   - 4/3 Directional Control Valve (4 ports, 3 positions)
     - Actuation: Lever / Manual
     - Return: Spring Centered
     - Type: Open Center (P connects to T in neutral)

3. Actuator:
   - Double-Acting Hydraulic Cylinder (Power Up / Power Down)

4. Conditioning:
   - Return Line Filter (between Valve and Tank)

CONNECTIONS:
- Suction Line: Tank -> Pump
- Pressure Line (P): Pump -> Relief Valve -> Directional Valve (Input)
- Working Lines (A/B): Directional Valve -> Cylinder (Head and Rod ends)
- Return Line (T): Directional Valve -> Filter -> Tank
- Drain/Relief: Relief Valve Outlet -> Tank
EOF

chown ga:ga /home/ga/Desktop/hydraulic_specs.txt
chmod 644 /home/ga/Desktop/hydraulic_specs.txt

# 3. Clean up previous runs
rm -f /home/ga/Desktop/forklift_hydraulic.drawio
rm -f /home/ga/Desktop/forklift_hydraulic.png

# 4. Launch draw.io
# We launch it and dismiss the dialog so the agent starts with a blank slate
# but the app is already running (convenience).
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
else
    DRAWIO_BIN="/usr/bin/drawio"
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (Escape key)
# This drops the user into a blank diagram or the main interface
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="