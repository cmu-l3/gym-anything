#!/bin/bash
echo "=== Setting up project_information_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/riverside_hub.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/riverside_project_brief.txt << 'SPECEOF'
PROJECT METADATA BRIEF
======================
Project:    Riverside Community Hub
Client:     Bristol City Council
Prepared:   Information Management Team
Date:       2024-03-15

INSTRUCTIONS
------------
The FZK-Haus model is currently loaded in BlenderBIM/Bonsai, but it contains
incorrect or default metadata. Your task is to update the IFC project metadata
to match the following requirements.

REQUIRED METADATA
-----------------
* Project Name:        Riverside Community Hub
* Project Description: Mixed-use community centre with library, cafe, and event spaces
* Project Phase:       Concept Design

* Organization Name:   Thornton Byrne Architects
* Person Family Name:  Okafor
* Person Given Name:   Adaeze

* Site Name:           Riverside Quarter
* Site Description:    Former industrial site on south bank of River Avon

* Building Name:       Community Hub Block A
* Building Description: Three-storey mixed-use building

* Postal Address:
    Town:              Bristol

DELIVERABLE
-----------
Update the fields using Bonsai's Project, Owner, and Spatial Hierarchy tools.
Save the updated model to:
/home/ga/BIMProjects/riverside_hub.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/riverside_project_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_metadata.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for metadata authoring task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for project info task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_metadata.py > /tmp/blender_task.log 2>&1 &"

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

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Brief: /home/ga/Desktop/riverside_project_brief.txt"
echo "Expected output: /home/ga/BIMProjects/riverside_hub.ifc"