#!/bin/bash
set -e
echo "=== Setting up constrain_mechanical_profile task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Generate the "broken" (under-constrained) file
# We use a python script running in FreeCAD to generate the geometry cleanly
cat > /tmp/generate_profile.py << 'PYEOF'
import FreeCAD, Part, Sketcher, os

doc_path = "/home/ga/Documents/FreeCAD/linkage_profile.FCStd"

# Create new document
if os.path.exists(doc_path):
    os.remove(doc_path)

doc = FreeCAD.newDocument("LinkageProfile")
sk = doc.addObject('Sketcher::SketchObject', 'LinkageSlot')

# Create Geometry: Slot shape
# Arc 1 (Left), Line 1 (Top), Arc 2 (Right), Line 2 (Bottom)
# Geometrically approx correct, but wrong sizes (e.g. length 50, radius 10)
geoList = []
geoList.append(Part.ArcOfCircle(Part.Circle(App.Vector(0,0,0), App.Vector(0,0,1), 10), 1.5708, 4.71239)) # Left Arc
geoList.append(Part.LineSegment(App.Vector(0,10,0), App.Vector(50,10,0))) # Top Line
geoList.append(Part.ArcOfCircle(Part.Circle(App.Vector(50,0,0), App.Vector(0,0,1), 10), 4.71239, 7.85398)) # Right Arc
geoList.append(Part.LineSegment(App.Vector(50,-10,0), App.Vector(0,-10,0))) # Bottom Line

sk.addGeometry(geoList, False)

# Add Geometric Constraints (Connectivity & Tangency & Horizontal)
# 0=Arc1, 1=Line1, 2=Arc2, 3=Line2
conList = []
# Tangent connections
conList.append(Sketcher.Constraint('Tangent',0,2,1,1)) # Arc1 end -> Line1 start
conList.append(Sketcher.Constraint('Tangent',1,2,2,1)) # Line1 end -> Arc2 start
conList.append(Sketcher.Constraint('Tangent',2,2,3,1)) # Arc2 end -> Line2 start
conList.append(Sketcher.Constraint('Tangent',3,2,0,1)) # Line2 end -> Arc1 start

# Horizontal lines
conList.append(Sketcher.Constraint('Horizontal', 1))
conList.append(Sketcher.Constraint('Horizontal', 3))

# Lock Left Arc Center to Origin (Critical anchor)
conList.append(Sketcher.Constraint('Coincident', 0, 3, -1, 1)) 

sk.addConstraint(conList)

# Recompute and Save
doc.recompute()
doc.saveAs(doc_path)
print(f"Generated {doc_path}")
PYEOF

# Run generation script headless
echo "Generating initial FreeCAD file..."
freecadcmd /tmp/generate_profile.py
chown ga:ga /home/ga/Documents/FreeCAD/linkage_profile.FCStd

# Record initial file state
stat -c %Y /home/ga/Documents/FreeCAD/linkage_profile.FCStd > /tmp/initial_file_mtime.txt

# Launch FreeCAD with the file
echo "Launching FreeCAD..."
kill_freecad
launch_freecad "/home/ga/Documents/FreeCAD/linkage_profile.FCStd"

# Wait for FreeCAD to load
wait_for_freecad 30

# Maximize window
maximize_freecad

# Configure view (optional, ensures sketch is visible if they open it)
# We can't easily enter the sketch automatically without interfering, 
# but we can ensure the Part/Sketcher workbench is loaded.
# (The user.cfg in env setup already handles some defaults)

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="