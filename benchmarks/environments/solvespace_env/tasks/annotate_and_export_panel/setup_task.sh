#!/bin/bash
echo "=== Setting up annotate_and_export_panel task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Remove previous output files
rm -f /home/ga/Documents/SolveSpace/divider_annotated.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/divider_annotate.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/divider_shop_drawing.dxf 2>/dev/null || true

# Verify the real sample file exists
if [ ! -f "/opt/solvespace_samples/divider.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/divider.slvs not found"
    exit 1
fi

FSIZE=$(stat -c%s "/opt/solvespace_samples/divider.slvs")
echo "Source file: /opt/solvespace_samples/divider.slvs ($FSIZE bytes)"

# Copy real divider.slvs to workspace as the starting file
cp /opt/solvespace_samples/divider.slvs /home/ga/Documents/SolveSpace/divider_annotate.slvs
chown ga:ga /home/ga/Documents/SolveSpace/divider_annotate.slvs

# Record task start timestamp AFTER file is in place
date +%s > /tmp/annotate_and_export_panel_start_ts

# Count existing constraints in the file as baseline
BASELINE=$(python3 << 'PYEOF'
import json
def count_constraints(fp):
    try:
        with open(fp, 'rb') as f:
            content = f.read()
        count = 0
        for part in content.split(b'\n\n'):
            if b'AddConstraint' in part:
                count += 1
        return count
    except:
        return -1
n = count_constraints('/home/ga/Documents/SolveSpace/divider_annotate.slvs')
print(n)
PYEOF
)

echo "$BASELINE" > /tmp/annotate_and_export_panel_baseline_count
echo "Baseline constraint count: $BASELINE"

# Drop the shop drawing specification on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/panel_spec.txt << 'SPECEOF'
SHOP DRAWING SPECIFICATION — WOODEN BOX DIVIDER PANEL
Job: Tutorial Box Assembly
CNC Router Programming Reference

REQUIRED DIMENSION ANNOTATIONS:
The machinist requires the following reference dimensions to be shown in the shop drawing:
- Overall panel width: 150 mm
- Overall panel height: 100 mm
- Corner notch depth: 25 mm

Output format: Export as DXF file for NC programming.
Issued by: Design Office
SPECEOF
chown ga:ga /home/ga/Desktop/panel_spec.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/divider_annotate.slvs"

echo "Waiting for SolveSpace to load divider_annotate.slvs..."
wait_for_solvespace 30
sleep 6

maximize_solvespace
sleep 1

take_screenshot /tmp/annotate_and_export_panel_start.png
echo "=== annotate_and_export_panel setup complete ==="
echo "Real divider.slvs loaded ($FSIZE bytes). Shop drawing specification at /home/ga/Desktop/panel_spec.txt"
