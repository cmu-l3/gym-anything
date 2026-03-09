#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up import_stl_convert_solid task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean previous artifacts
rm -f /home/ga/Documents/FreeCAD/bracket_solid.FCStd
rm -f /home/ga/Documents/FreeCAD/scanned_bracket.stl
rm -f /tmp/expected_volume.txt

# Ensure source FCStd exists (provided by env setup)
SOURCE_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
if [ ! -f "$SOURCE_FILE" ]; then
    # Fallback to copy from opt if missing in Docs
    if [ -f "/opt/freecad_samples/T8_housing_bracket.FCStd" ]; then
        cp /opt/freecad_samples/T8_housing_bracket.FCStd "$SOURCE_FILE"
    else
        echo "ERROR: T8_housing_bracket.FCStd not found"
        exit 1
    fi
fi

# Export STL and record ground truth volume using FreeCAD headless
echo "Generating STL and calculating ground truth volume..."
su - ga -c 'freecadcmd /dev/stdin' <<PYEOF > /tmp/generation.log 2>&1
import sys
import FreeCAD
import Mesh
import Part

try:
    doc = FreeCAD.openDocument("$SOURCE_FILE")
    
    exported = False
    volume = 0.0
    
    # Find the main solid
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and (obj.Shape.ShapeType == 'Solid' or len(obj.Shape.Solids) > 0):
            if obj.Shape.Volume > 100: # Filter out tiny artifacts
                volume = obj.Shape.Volume
                
                # Write expected volume to file
                with open("/tmp/expected_volume.txt", "w") as f:
                    f.write(str(volume))
                
                # Export with fine tessellation for realistic "scan" quality
                # 0.05mm is a reasonable scan resolution
                mesh = Mesh.Mesh(obj.Shape.tessellate(0.05))
                mesh.write("/home/ga/Documents/FreeCAD/scanned_bracket.stl")
                print(f"Exported STL: {volume} mm3")
                exported = True
                break
    
    if not exported:
        print("Error: No solid found to export")
        sys.exit(1)

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF

# Verify generation success
if [ ! -f /home/ga/Documents/FreeCAD/scanned_bracket.stl ]; then
    echo "ERROR: STL generation failed"
    cat /tmp/generation.log
    exit 1
fi

echo "Expected Volume: $(cat /tmp/expected_volume.txt)"
chown ga:ga /home/ga/Documents/FreeCAD/scanned_bracket.stl

# Kill any existing FreeCAD
kill_freecad

# Launch FreeCAD with NO file (empty start)
# We want the agent to do the import manually
launch_freecad

# Wait for FreeCAD window
wait_for_freecad 45

# Maximize and focus
maximize_freecad
sleep 2

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="