#!/bin/bash
echo "=== Setting up site_georeferencing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_georeferenced.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create site survey specification document on Desktop ───────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/site_survey_report.txt << 'SPECEOF'
SITE SURVEY AND GEOREFERENCING REPORT
=====================================
Project: FZK-Haus Test Building
Location: KIT Campus South, Karlsruhe, Germany
Date: 2024-03-15
Reference: SURVEY-2024-FZK-001

INSTRUCTIONS FOR BIM COORDINATOR
--------------------------------
The architectural IFC model must be georeferenced before integration 
with the site GIS model and utility routing.

COORDINATE REFERENCE SYSTEM (CRS)
---------------------------------
System: ETRS89 / UTM zone 32N
EPSG Code: 25832
Map Projection: Transverse Mercator

MAP CONVERSION COORDINATES (Insertion Point)
--------------------------------------------
Easting (X): 456568.0
Northing (Y): 5429834.0
Orthogonal Height (Z): 115.0 (m above sea level)
True North Angle: 0 degrees

OUTPUT
------
Apply these settings using Bonsai's Georeferencing tools.
Save the georeferenced IFC project to:
/home/ga/BIMProjects/fzk_georeferenced.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/site_survey_report.txt
echo "Survey documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_georef.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for georeferencing task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_georef.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to load
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
echo "Survey report: /home/ga/Desktop/site_survey_report.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_georeferenced.ifc"