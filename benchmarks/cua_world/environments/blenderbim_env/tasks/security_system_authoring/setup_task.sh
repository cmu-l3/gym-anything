#!/bin/bash
echo "=== Setting up security_system_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown -R ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_security_system.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create security specification brief ────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/security_brief.txt << 'SPECEOF'
SECURITY & ACCESS CONTROL BRIEF
================================
Project:    FZK-Haus Residential Conversion
Client:     FZK Property Management
Discipline: ELV / Security
Date:       2024-03-15

SCOPE
-----
The FZK-Haus IFC model is currently loaded in BlenderBIM/Bonsai.
You need to integrate an access control and surveillance system
into the model for FM handover.

DELIVERABLE
-----------
Model the required security devices, assign their correct IFC classes,
group them into a logical system, and save the model to:
  /home/ga/BIMProjects/fzk_security_system.ifc

REQUIREMENTS
------------

1. ACCESS CONTROL DEVICES
   - Model at least 2 card readers (e.g., small boxes near doors)
   - Assign IFC Class: IfcSecurityAppliance

2. SURVEILLANCE CAMERAS
   - Model at least 2 CCTV cameras (e.g., small cylinders/domes on exterior walls)
   - Assign IFC Class: IfcCommunicationsAppliance (or IfcSensor)

3. LOGICAL SYSTEM GROUPING
   - Create a new Distribution System (IfcDistributionSystem)
   - Name the system "Security System" (or ensure it contains "Security" or "Surveillance")
   - Assign ALL of the newly created security and communication appliances
     to this distribution system using Bonsai's system assignment tools.

NOTES:
  - Simple 3D mesh geometry is perfectly acceptable for the devices.
  - The critical requirement is correct IFC classification and system grouping.
  - Use Bonsai's "Save IFC Project" to generate the output file.
SPECEOF
chown ga:ga /home/ga/Desktop/security_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_security.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the security task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for security task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_security.py > /tmp/blender_task.log 2>&1 &"

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
sleep 10

# ── 8. Focus, maximize, screenshot ────────────────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Spec: /home/ga/Desktop/security_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_security_system.ifc"