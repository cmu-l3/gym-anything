#!/bin/bash
echo "=== Setting up geofence_safety_setup task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief (agent must read this to get field/hazard coords)
cat > /home/ga/Documents/QGC/ops_brief.txt << 'OPDOC'
AGRICULTURAL DRONE OPERATIONS BRIEF
Campaign: Wheat Field Crop Spray – Sector B
Operator: AgroFly Solutions AG
Date: 2026-03-09

=== APPROVED FLIGHT AREA (INCLUSION FENCE) ===
You must draw an INCLUSION polygon with at least 5 vertices covering the
approved agricultural field. The polygon must enclose the entire field area.

Suggested polygon vertices (draw in order):
  P1: 47.4010°N, 8.5400°E  (NW corner)
  P2: 47.4010°N, 8.5520°E  (NE corner)
  P3: 47.3990°N, 8.5540°E  (E edge midpoint)
  P4: 47.3950°N, 8.5520°E  (SE corner)
  P5: 47.3940°N, 8.5420°E  (SW corner)
  P6: 47.3960°N, 8.5380°E  (W edge midpoint)

Note: You MUST use the Fence > Inclusion Polygon tool (not a mission polygon).
The fence type must be INCLUSION (approved area), NOT exclusion.

=== EXCLUSION ZONE — POWER SUBSTATION ===
There is a power substation inside the field that poses electromagnetic
interference risk. You must create an EXCLUSION zone around it.

Substation center: 47.3980°N, 8.5465°E
Required exclusion radius: 80 m minimum
Use an exclusion circle OR exclusion polygon around this point.

The drone must NOT enter the exclusion zone.

=== RALLY POINTS (EMERGENCY LANDING ZONES) ===
Place at least 2 Rally Points at safe emergency landing locations:
  RL1 (suggested): 47.3985°N, 8.5430°E  (clear patch NW of substation)
  RL2 (suggested): 47.3970°N, 8.5500°E  (clear patch SE of substation)

Rally points must be within the inclusion fence, outside the exclusion zone.

=== REQUIRED ARDUPILOT SAFETY PARAMETERS ===
After saving the fence plan, set these parameters in Vehicle Setup > Parameters:

  FENCE_ACTION = 1
  (Value 1 = RTL on fence breach. Default is 0 which just reports — NOT acceptable.)

  RTL_ALT = 2500
  (2500 cm = 25 m return altitude. Low-altitude ag ops standard.)

=== OUTPUT FILE ===
Save the complete geofence plan (inclusion + exclusion + rally points) to:
  /home/ga/Documents/QGC/safety_fence.plan

The plan file must contain the inclusion polygon, exclusion zone, AND rally points.
OPDOC

chown ga:ga /home/ga/Documents/QGC/ops_brief.txt

# 3. Record task start time
date +%s > /tmp/task_start_time

# 4. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== geofence_safety_setup task setup complete ==="
echo "Operations brief: /home/ga/Documents/QGC/ops_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/safety_fence.plan"
