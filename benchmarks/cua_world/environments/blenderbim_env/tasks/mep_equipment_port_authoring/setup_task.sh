#!/bin/bash
echo "=== Setting up mep_equipment_port_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/arcticflow_chiller.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create product specification brief ─────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/arcticflow_chiller_spec.txt << 'SPECEOF'
PRODUCT BIM AUTHORING SPECIFICATION
=====================================
Manufacturer:   ArcticFlow Systems
Product Line:   AF-Series Commercial Chillers
Model:          AF-500
Standard:       IFC4

TASK DESCRIPTION
----------------
As a BIM Content Developer, create a standalone IFC model for the 
AF-500 Commercial Chiller. Consulting engineers will place this 
IFC file into their building models, so it MUST contain proper 
MEP logical connection ports.

REQUIREMENTS
------------
1. GEOMETRY & CLASSIFICATION
   - Create representative 3D geometry for the chiller unit.
   - Assign the IFC class: IfcChiller (or IfcEnergyConversionDevice).

2. LOGICAL PORTS (CRITICAL)
   - The chiller must have at least TWO connection ports to allow 
     connection to chilled water piping.
   - Use Bonsai's MEP/Port tools to add IfcDistributionPort entities.
   - The ports MUST be assigned/nested to the chiller equipment.

3. MANUFACTURER DATA
   - Add the property set: Pset_ManufacturerTypeInformation
   - Set the 'Manufacturer' property exactly to: ArcticFlow

4. DELIVERABLE
   - Save the IFC project to: /home/ga/BIMProjects/arcticflow_chiller.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/arcticflow_chiller_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Launch Blender (empty session) ─────────────────────────────────────
echo "Launching Blender (empty session for product modeling)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

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
sleep 3

# ── 7. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session"
echo "Brief: /home/ga/Desktop/arcticflow_chiller_spec.txt"
echo "Expected output: /home/ga/BIMProjects/arcticflow_chiller.ifc"