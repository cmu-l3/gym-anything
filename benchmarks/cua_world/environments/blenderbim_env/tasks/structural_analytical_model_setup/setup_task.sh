#!/bin/bash
echo "=== Setting up structural_analytical_model_setup task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists and is clean
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects
rm -f /home/ga/BIMProjects/analytical_frame.ifc 2>/dev/null || true

# 2. Kill any existing Blender instances
kill_blender

# 3. Create a brief document on the Desktop for the agent's reference
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/structural_analysis_brief.txt << 'SPECEOF'
STRUCTURAL ANALYTICAL MODEL BRIEF
==================================
Project: Steel Portal Frame Analysis
Date: 2024-03-15

TASK:
Initialize a structural analytical model in BlenderBIM/Bonsai for FEA export.

REQUIREMENTS:
1. Create a new IFC4 project.
2. Create a Structural Analysis Model container (IfcStructuralAnalysisModel).
3. Model at least two support nodes (IfcStructuralPointConnection).
4. Model at least one 1D structural member (IfcStructuralCurveMember).
5. Save the file exactly to: /home/ga/BIMProjects/analytical_frame.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/structural_analysis_brief.txt
echo "Project brief placed on Desktop"

# 4. Record task start timestamp for anti-gaming verification
date +%s.%N > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 5. Launch an empty Blender session
echo "Launching empty Blender session..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window to appear
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

# 6. Focus, maximize, and dismiss any startup dialogs
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1

# Take an initial screenshot proving we start from a clean state
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="