#!/bin/bash
echo "=== Setting up iot_sensor_network_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_iot_sensors.ifc 2>/dev/null || true
rm -f /tmp/sensor_network_result.json 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the IoT specification document on Desktop ───────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/iot_sensor_spec.txt << 'SPECEOF'
SMART BUILDING IOT SENSOR NETWORK SPECIFICATION
=================================================
Project: FZK-Haus Retrofit
Client: FZK Institute Smart Campus
Date: 2024-03-15
Reference: IOT-SPEC-2024-001

INSTRUCTIONS
------------
Using Bonsai (BlenderBIM), add an IoT sensor network to the
FZK-Haus model currently open in the application.

STEP 1: Create IFC Types
  - Navigate to Bonsai's Project Setup / Project Library
  - Create at least TWO distinct `IfcSensorType` definitions
    to represent the manufacturer products (e.g., "Acme Smoke Detector",
    "SmartTemp Thermostat").

STEP 2: Model Sensor Occurrences
  - Place simple proxy geometry (e.g., small cubes or cylinders)
    in logical locations (ceilings for smoke detectors, walls for thermostats).
  - Assign the `IfcSensor` class to these objects.
  - Link them to the `IfcSensorType` definitions you created.
  - Model a minimum of 5 sensors total.

STEP 3: Assign Predefined Types
  - Ensure the correct IFC4 PredefinedType is assigned (either on
    the occurrence or the type definition).
  - You must use at least 3 distinct types from this list:
      * SMOKESENSOR
      * TEMPERATURESENSOR
      * MOVEMENTSENSOR
      * CO2SENSOR
      * LIGHTSENSOR

STEP 4: Spatial Containment
  - Ensure all placed sensors are spatially contained within the
    correct `IfcBuildingStorey` (Ground Floor or First Floor).

STEP 5: Save Project
  - Save the completed IFC file to:
    /home/ga/BIMProjects/fzk_iot_sensors.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/iot_sensor_spec.txt
echo "Specification document placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_iot.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for IoT modeling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_iot.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 15 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Extra time for IFC to fully load into Bonsai
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Spec document: /home/ga/Desktop/iot_sensor_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_iot_sensors.ifc"