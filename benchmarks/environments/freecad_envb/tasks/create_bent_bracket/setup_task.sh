#!/bin/bash
set -e
echo "=== Setting up create_bent_bracket task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Clean up previous run
rm -f /home/ga/Documents/FreeCAD/bracket_profile.FCStd
rm -f /home/ga/Documents/FreeCAD/finished_bracket.FCStd

# ==============================================================================
# Generate the starting state file programmatically
# This ensures a clean, verifiable starting state every time
# ==============================================================================
cat > /tmp/generate_profile.py << 'PYEOF'
import FreeCAD
import Part
import Sketcher

doc = FreeCAD.newDocument("BracketProfile")
doc.FileName = "/home/ga/Documents/FreeCAD/bracket_profile.FCStd"

# Create the Z-profile sketch
sketch = doc.addObject('Sketcher::SketchObject', 'ProfileSketch')
sketch.MapMode = 'FlatFace'

# Geometry: Z-shape polyline (Open profile)
# (0,0) -> (30,0) -> (30,40) -> (60,40)
lines = []
lines.append(Part.LineSegment(FreeCAD.Vector(0,0,0), FreeCAD.Vector(30,0,0)))
lines.append(Part.LineSegment(FreeCAD.Vector(30,0,0), FreeCAD.Vector(30,40,0)))
lines.append(Part.LineSegment(FreeCAD.Vector(30,40,0), FreeCAD.Vector(60,40,0)))

for line in lines:
    sketch.addGeometry(line)

# Add constraints to make it robust
sketch.addConstraint(Sketcher.Constraint('Coincident', 0, 2, 1, 1))
sketch.addConstraint(Sketcher.Constraint('Coincident', 1, 2, 2, 1))
sketch.addConstraint(Sketcher.Constraint('Horizontal', 0))
sketch.addConstraint(Sketcher.Constraint('Vertical', 1))
sketch.addConstraint(Sketcher.Constraint('Horizontal', 2))

# Dimensions
sketch.addConstraint(Sketcher.Constraint('DistanceX', 0, 1, 0, 2, 30.0)) # First seg length
sketch.addConstraint(Sketcher.Constraint('DistanceY', 1, 1, 1, 2, 40.0)) # Vertical seg length
sketch.addConstraint(Sketcher.Constraint('DistanceX', 2, 1, 2, 2, 30.0)) # Last seg length

doc.recompute()
doc.save()
print("Generated bracket_profile.FCStd")
PYEOF

# Run generation script headless
echo "Generating input file..."
su - ga -c "freecadcmd /tmp/generate_profile.py"

# ==============================================================================
# Launch FreeCAD with the file
# ==============================================================================
echo "Launching FreeCAD..."
launch_freecad "/home/ga/Documents/FreeCAD/bracket_profile.FCStd"

# Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# Ensure Part workbench is loaded (optional, but helpful context)
# We won't force the workbench switch as that's part of the task, 
# but we ensure the app is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="