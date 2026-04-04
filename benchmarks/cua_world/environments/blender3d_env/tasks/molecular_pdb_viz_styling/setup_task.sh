#!/bin/bash
echo "=== Setting up molecular_pdb_viz_styling task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# ================================================================
# GENERATE REAL PDB DATA (Caffeine - CID 2519)
# ================================================================
PDB_FILE="/home/ga/Documents/caffeine.pdb"
cat > "$PDB_FILE" << 'EOF'
HEADER    ALKALOID                                27-FEB-26   XXXX              
TITLE     CAFFEINE MOLECULE STRUCTURE
COMPND    MOL_ID: 1;
COMPND   2 MOLECULE: CAFFEINE;
COMPND   3 CHAIN: A;
COMPND   4 SYNONYM: 1,3,7-TRIMETHYLXANTHINE
HETATM    1  N1  LIG A   1      -0.076   0.244  -0.083  1.00  0.00           N  
HETATM    2  C2  LIG A   1       1.229   0.612  -0.098  1.00  0.00           C  
HETATM    3  O2  LIG A   1       2.148  -0.197  -0.192  1.00  0.00           O  
HETATM    4  N3  LIG A   1       1.558   1.986   0.007  1.00  0.00           N  
HETATM    5  C4  LIG A   1       2.924   2.457  -0.015  1.00  0.00           C  
HETATM    6  C5  LIG A   1       0.510   2.894   0.117  1.00  0.00           C  
HETATM    7  C6  LIG A   1      -0.784   2.080   0.085  1.00  0.00           C  
HETATM    8  O6  LIG A   1      -1.921   2.502   0.165  1.00  0.00           O  
HETATM    9  C1' LIG A   1      -0.548  -1.196  -0.151  1.00  0.00           C  
HETATM   10  N7  LIG A   1       0.834   4.256   0.222  1.00  0.00           N  
HETATM   11  C8  LIG A   1      -0.278   5.178   0.281  1.00  0.00           C  
HETATM   12  C3' LIG A   1       2.147   4.630   0.267  1.00  0.00           C  
HETATM   13  N9  LIG A   1       2.607   3.497   0.137  1.00  0.00           N  
CONECT    1    2    7    9
CONECT    2    1    3    4
CONECT    3    2
CONECT    4    2    5    6
CONECT    5    4   13
CONECT    6    4    7   10
CONECT    7    1    6    8
CONECT    8    7
CONECT    9    1
CONECT   10    6   11   12
CONECT   11   10
CONECT   12   10   13
CONECT   13   12    5
END
EOF
chown ga:ga "$PDB_FILE"

# Clean previous outputs
rm -f /home/ga/BlenderProjects/molecular_setup.blend
rm -f /home/ga/BlenderProjects/caffeine_viz.png

# Ensure Blender is running (clean state)
pkill -x blender 2>/dev/null || true
sleep 1

# Start Blender maximized
echo "Starting Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        break
    fi
    sleep 1
done

# Maximize and focus
maximize_blender
focus_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="