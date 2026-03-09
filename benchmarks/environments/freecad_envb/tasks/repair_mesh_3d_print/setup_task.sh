#!/bin/bash
set -e
echo "=== Setting up repair_mesh_3d_print task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Clean up previous runs
rm -f /home/ga/Documents/FreeCAD/damaged_bracket.stl
rm -f /home/ga/Documents/FreeCAD/ready_to_print.stl

# ------------------------------------------------------------------
# GENERATE DAMAGED MESH
# We use FreeCAD to procedurally generate a broken STL from the real 
# sample file T8_housing_bracket.FCStd
# ------------------------------------------------------------------
cat > /tmp/generate_damaged_mesh.py << 'EOF'
import FreeCAD
import Part
import Mesh
import sys
import random

try:
    # Open the real sample file provided in the environment
    # Note: T8_housing_bracket.FCStd is mounted into /opt/freecad_samples/
    input_path = "/opt/freecad_samples/T8_housing_bracket.FCStd"
    doc = FreeCAD.open(input_path)
    
    # Find the main solid object
    solid_obj = None
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.Volume > 5000:
            solid_obj = obj
            break
            
    if not solid_obj:
        print("Error: No valid solid found in sample file")
        sys.exit(1)
        
    print(f"Meshing object: {solid_obj.Name}")
    
    # Tessellate to create a mesh (0.5mm precision)
    mesh_obj = Mesh.Mesh(solid_obj.Shape.tessellate(0.5))
    
    # DAMAGE THE MESH: Remove random facets to create holes
    # We pick a random start index and remove a chunk
    count = mesh_obj.CountFacets
    facets_to_remove = []
    
    # Create 3 distinct holes
    for _ in range(3):
        start = random.randint(0, count - 50)
        # Remove a patch of 30 facets
        for i in range(start, start + 30):
            facets_to_remove.append(i)
            
    mesh_obj.removeFacets(list(set(facets_to_remove)))
    
    output_path = "/home/ga/Documents/FreeCAD/damaged_bracket.stl"
    mesh_obj.write(output_path)
    print(f"Damaged mesh saved to {output_path}")

except Exception as e:
    print(f"Error generating mesh: {e}")
    sys.exit(1)
EOF

echo "Generating damaged input file..."
su - ga -c "freecadcmd /tmp/generate_damaged_mesh.py"
rm /tmp/generate_damaged_mesh.py

# ------------------------------------------------------------------
# SETUP DESKTOP ENVIRONMENT
# ------------------------------------------------------------------

# Launch FreeCAD (GUI)
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Open file browser to show the user the file exists
su - ga -c "nautilus /home/ga/Documents/FreeCAD &"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="