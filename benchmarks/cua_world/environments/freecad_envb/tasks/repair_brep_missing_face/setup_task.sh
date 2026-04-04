#!/bin/bash
set -e
echo "=== Setting up Repair Broken B-Rep Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f freecad 2>/dev/null || true
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/broken_bracket.FCStd
rm -f /home/ga/Documents/FreeCAD/repaired_bracket.FCStd

# -----------------------------------------------------------------------------
# GENERATE BROKEN GEOMETRY
# We programmatically create the "broken" file by loading the real T8 bracket,
# exploding it into faces, removing one, and saving the result as a Shell.
# -----------------------------------------------------------------------------
echo "Generating broken geometry from ground truth..."

cat > /tmp/generate_broken_model.py << 'PYEOF'
import FreeCAD
import Part
import sys

try:
    # Load ground truth
    src_path = "/opt/freecad_samples/T8_housing_bracket.FCStd"
    doc = FreeCAD.openDocument(src_path)
    
    # Find the solid
    solid_obj = None
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.ShapeType == 'Solid':
            solid_obj = obj
            break
            
    if not solid_obj:
        print("Error: No solid found in ground truth")
        sys.exit(1)
        
    # Get faces
    faces = solid_obj.Shape.Faces
    print(f"Original face count: {len(faces)}")
    
    # Identify a good face to remove. 
    # We want a noticeable planar face. The T8 bracket base is usually a large plane.
    # We sort by area and pick a large one, but not the largest (which might be the complex curved top)
    # Actually, the base is likely the largest planar face.
    sorted_faces = sorted(faces, key=lambda f: f.Area, reverse=True)
    
    # Remove the 2nd largest face (usually a major side or bottom) to ensure it's obvious
    face_to_remove = sorted_faces[0] 
    
    # Keep all faces EXCEPT the specific one
    # Note: BRep shapes compare by reference, so we need to filter carefully
    faces_to_keep = []
    for f in faces:
        if not f.isSame(face_to_remove):
            faces_to_keep.append(f)
            
    print(f"Keeping {len(faces_to_keep)} faces")
    
    # Create a Shell from the remaining faces
    shell = Part.makeShell(faces_to_keep)
    
    # Create new document for the broken part
    new_doc = FreeCAD.newDocument("BrokenBracket")
    feature = new_doc.addObject("Part::Feature", "BrokenGeometry")
    feature.Shape = shell
    
    # Save
    out_path = "/home/ga/Documents/FreeCAD/broken_bracket.FCStd"
    new_doc.saveAs(out_path)
    print(f"Saved broken model to {out_path}")
    
except Exception as e:
    print(f"Error generating geometry: {e}")
    sys.exit(1)
PYEOF

# Run generation script
su - ga -c "freecadcmd /tmp/generate_broken_model.py"

if [ ! -f /home/ga/Documents/FreeCAD/broken_bracket.FCStd ]; then
    echo "ERROR: Failed to generate broken_bracket.FCStd"
    exit 1
fi

# -----------------------------------------------------------------------------
# LAUNCH APPLICATION
# -----------------------------------------------------------------------------

echo "Launching FreeCAD with broken model..."
launch_freecad "/home/ga/Documents/FreeCAD/broken_bracket.FCStd"

# Wait for window
wait_for_freecad 30

# Maximize
maximize_freecad

# -----------------------------------------------------------------------------
# RECORD INITIAL STATE
# -----------------------------------------------------------------------------
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="