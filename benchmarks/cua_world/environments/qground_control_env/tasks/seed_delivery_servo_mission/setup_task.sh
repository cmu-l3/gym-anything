#!/bin/bash
echo "=== Setting up seed_delivery_servo_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory and clear old files
mkdir -p /home/ga/Documents/QGC
rm -f /home/ga/Documents/QGC/seed_delivery.plan 2>/dev/null || true
chown ga:ga /home/ga/Documents/QGC

# 2. Write the delivery specification document
cat > /home/ga/Documents/QGC/delivery_spec.txt << 'SPECDOC'
═══════════════════════════════════════════════════
  PRECISION SEEDING DELIVERY PLAN
  Farm: Henderson Ag Research Station
  Date: 2026-03-09
  Agronomist: Dr. K. Marsden
═══════════════════════════════════════════════════

AIRCRAFT CONFIGURATION
  Frame: QuadCopter with belly-mounted seed hopper
  Hopper Servo Channel: 9
  Hopper OPEN PWM:  1100 µs
  Hopper CLOSE PWM: 1900 µs
  Dispersal Hold Time: 5 seconds per location

FLIGHT PARAMETERS
  Takeoff Altitude: 25 m AGL
  Cruise Altitude:  25 m AGL

DELIVERY LOCATIONS (WGS84)
  Location 1 — North paddock cover crop zone:
    Latitude:  -35.36180
    Longitude: 149.16650

  Location 2 — South paddock erosion strip:
    Latitude:  -35.36420
    Longitude: 149.16750

MISSION SEQUENCE (per location):
  1. Fly to delivery waypoint
  2. Set servo channel 9 to 1100 (open hopper)
  3. Hold/delay 5 seconds for seed dispersal
  4. Set servo channel 9 to 1900 (close hopper)
  5. Proceed to next location or RTL

NOTES
  - Ensure RTL is the final command
  - All altitudes are relative to home position
  - Do NOT arm the vehicle; save the plan file only
═══════════════════════════════════════════════════
SPECDOC

chown ga:ga /home/ga/Documents/QGC/delivery_spec.txt

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time

# 4. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot as evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== seed_delivery_servo_mission task setup complete ==="
echo "Spec document: /home/ga/Documents/QGC/delivery_spec.txt"
echo "Expected output: /home/ga/Documents/QGC/seed_delivery.plan"