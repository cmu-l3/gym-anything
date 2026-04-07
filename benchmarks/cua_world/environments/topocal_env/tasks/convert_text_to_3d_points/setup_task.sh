#!/bin/bash
echo "=== Setting up convert_text_to_3d_points task ==="

# Create standard temp directory if missing
mkdir -p /c/temp 2>/dev/null || mkdir -p C:/temp 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > C:/temp/task_start_time.txt 2>/dev/null || echo $(date +%s) > /c/temp/task_start_time.txt

# Use Python (native in the environment) to generate the precise DXF and Ground Truth
# This sidesteps Windows/Bash path translation issues natively
cat << 'EOF' > C:/temp/setup_data.py
import os
import random
import time
import subprocess

data_dir = r"C:\workspace\data"
gt_dir = r"C:\workspace\data\ground_truth"

os.makedirs(data_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

dxf_path = os.path.join(data_dir, "legacy_topo_texts.dxf")
gt_path = os.path.join(gt_dir, "true_coordinates.csv")

# Generate standard DXF header/footer
dxf_header = "  0\nSECTION\n  2\nENTITIES\n"
dxf_footer = "  0\nENDSEC\n  0\nEOF\n"

random.seed(42)  # Deterministic real-world distribution for Foothills UTM 13N

with open(dxf_path, 'w') as fdxf, open(gt_path, 'w') as fgt:
    fdxf.write(dxf_header)
    fgt.write("Point,X,Y,Z\n")
    
    for i in range(1, 86):
        # Generate realistic Colorado UTM Zone 13N coordinates
        x = 480000.0 + random.uniform(0, 500)
        y = 4400000.0 + random.uniform(0, 500)
        z = 1840.0 + random.uniform(0, 40)
        
        # Write true coordinates to ground truth
        fgt.write(f"{i},{x:.3f},{y:.3f},{z:.3f}\n")
        
        # Write flat text entity to DXF (Z=0, text string = true Z)
        fdxf.write("  0\nTEXT\n  8\n0\n")
        fdxf.write(f" 10\n{x:.3f}\n 20\n{y:.3f}\n 30\n0.0\n")
        fdxf.write(f" 40\n2.0\n  1\n{z:.3f}\n")
        
    fdxf.write(dxf_footer)

# Ensure TopoCal is running
try:
    output = subprocess.check_output('tasklist', shell=True).decode()
    if 'TopoCal.exe' not in output:
        subprocess.Popen([r"C:\Program Files (x86)\TopoCal\TopoCal.exe"])
        time.sleep(6)
except Exception as e:
    print(f"Error starting TopoCal: {e}")

# Take initial screenshot
try:
    from PIL import ImageGrab
    im = ImageGrab.grab()
    im.save(r'C:\temp\task_initial.png')
except:
    pass
EOF

# Execute the python setup
python C:/temp/setup_data.py || python.exe C:/temp/setup_data.py

echo "=== Setup complete ==="