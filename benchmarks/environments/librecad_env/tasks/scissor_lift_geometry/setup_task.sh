#!/bin/bash
set -e
echo "=== Setting up Scissor Lift Geometry Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/LibreCAD/scissor_lift_study.dxf
rm -f /home/ga/Documents/lift_specs.txt
mkdir -p /home/ga/Documents/LibreCAD

# 3. Create the specifications file
# Using specific values that the verifier will check against
cat > /home/ga/Documents/lift_specs.txt << EOF
PROJECT: SL-3000-2 Kinematic Study
TYPE: Double-Stage Scissor Lift (Stacked)
ARM LENGTH: 3000 mm (center-to-center)
DEPLOYMENT ANGLE: 35 degrees (from horizontal)
PIN DIAMETER: 40 mm
PLATFORM OVERHANG: 0 mm (flush with arms)
EOF

chown ga:ga /home/ga/Documents/lift_specs.txt

# 4. Start LibreCAD
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
    sleep 5
fi

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="