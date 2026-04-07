#!/bin/bash
echo "=== Setting up openvsp_high_lift_deployment ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/OpenVSP/exports
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/OpenVSP
chown -R ga:ga /home/ga/Desktop

# Copy the baseline model
cp /workspace/data/eCRM-001_wing_tail.vsp3 /home/ga/Documents/OpenVSP/transport_baseline.vsp3
chmod 644 /home/ga/Documents/OpenVSP/transport_baseline.vsp3

# Remove any stale outputs
rm -f /home/ga/Documents/OpenVSP/transport_takeoff.vsp3
rm -f /home/ga/Documents/OpenVSP/exports/takeoff_mesh.stl
rm -f /tmp/high_lift_result.json

# Write the takeoff configuration schedule
cat > /home/ga/Desktop/takeoff_schedule.txt << 'EOF'
TAKEOFF CONFIGURATION SCHEDULE - FLIGHT STATE 2A
================================================
Aircraft: Regional Transport eCRM
Configuration: Takeoff (High-Lift)

Set the following control surface deflections in the master model:
(Note: Positive values generally indicate trailing-edge down)

Main Wing Surfaces:
- FlapInboard  : +20.0 deg
- FlapOutboard : +15.0 deg
- Slat         : -25.0 deg  (Leading-edge droop)

Horizontal Tail Surfaces:
- Elevator     : -8.0 deg   (Nose-up pitch trim)

Instructions:
1. Open the model: /home/ga/Documents/OpenVSP/transport_baseline.vsp3
2. If the sub-surfaces are not already present, create them first as 'Control Surface' types under the Sub-Surface tab of the respective components.
3. Apply the deflection angles using the 'Deflect' parameter in the Sub-Surface panel.
4. Save the new model as 'transport_takeoff.vsp3' in the OpenVSP Documents folder.
5. Export the deflected geometry as an STL mesh named 'takeoff_mesh.stl' in the exports/ folder.
EOF
chmod 644 /home/ga/Desktop/takeoff_schedule.txt
chown ga:ga /home/ga/Desktop/takeoff_schedule.txt

# Kill any existing OpenVSP instances
kill_openvsp

# Launch OpenVSP with the baseline model
launch_openvsp "/home/ga/Documents/OpenVSP/transport_baseline.vsp3"

# Wait for OpenVSP window and focus it
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="