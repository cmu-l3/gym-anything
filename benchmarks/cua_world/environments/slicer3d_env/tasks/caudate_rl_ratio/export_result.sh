#!/bin/bash
echo "=== Exporting Caudate-RL Ratio Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get patient number
PATIENT_NUM=$(cat /tmp/task_patient_num.txt 2>/dev/null || echo "5")

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/crl_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer
    cat > /tmp/export_crl_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

measurements = {"caudate": None, "rightlobe": None}

# Get all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        measurement = {
            "name": node.GetName(),
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_level": (p1[2] + p2[2]) / 2
        }
        
        print(f"  {node.GetName()}: {length:.1f} mm at z={measurement['z_level']:.1f}")
        
        # Try to identify which measurement this is
        if "caudate" in name:
            measurements["caudate"] = measurement
        elif "right" in name or "rl" in name:
            measurements["rightlobe"] = measurement
        elif measurements["caudate"] is None:
            measurements["caudate"] = measurement
        elif measurements["rightlobe"] is None:
            measurements["rightlobe"] = measurement

# Save individual measurement files
if measurements["caudate"]:
    caudate_path = os.path.join(output_dir, "caudate_measurement.mrk.json")
    with open(caudate_path, "w") as f:
        json.dump(measurements["caudate"], f, indent=2)
    print(f"Saved caudate measurement to {caudate_path}")

if measurements["rightlobe"]:
    rightlobe_path = os.path.join(output_dir, "rightlobe_measurement.mrk.json")
    with open(rightlobe_path, "w") as f:
        json.dump(measurements["rightlobe"], f, indent=2)
    print(f"Saved rightlobe measurement to {rightlobe_path}")

print("Export complete")
PYEOF

    # Run export in background
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_crl_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_crl_markups" 2>/dev/null || true
fi

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
AGENT_CAUDATE=""
AGENT_RIGHTLOBE=""
AGENT_RATIO=""
AGENT_CLASSIFICATION=""
AGENT_SLICE=""

POSSIBLE_REPORT_PATHS=(
    "$IRCADB_DIR/crl_ratio_report.json"
    "$IRCADB_DIR/report.json"
    "/home/ga/Documents/crl_ratio_report.json"
    "/home/ga/crl_ratio_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Parse report fields (try multiple field names)
        AGENT_CAUDATE=$(python3 -c "
import json
d = json.load(open('$path'))
for key in ['caudate_width_mm', 'caudate_width', 'caudate', 'caudate_mm']:
    if key in d:
        print(d[key])
        break
" 2>/dev/null || echo "")
        
        AGENT_RIGHTLOBE=$(python3 -c "
import json
d = json.load(open('$path'))
for key in ['rightlobe_width_mm', 'right_lobe_width_mm', 'rightlobe_width', 'right_lobe_width', 'rightlobe', 'right_lobe']:
    if key in d:
        print(d[key])
        break
" 2>/dev/null || echo "")
        
        AGENT_RATIO=$(python3 -c "
import json
d = json.load(open('$path'))
for key in ['crl_ratio', 'ratio', 'c_rl_ratio', 'cl_ratio']:
    if key in d:
        print(d[key])
        break
" 2>/dev/null || echo "")
        
        AGENT_CLASSIFICATION=$(python3 -c "
import json
d = json.load(open('$path'))
for key in ['classification', 'class', 'diagnosis', 'assessment']:
    if key in d:
        print(d[key])
        break
" 2>/dev/null || echo "")
        
        AGENT_SLICE=$(python3 -c "
import json
d = json.load(open('$path'))
for key in ['slice_level', 'slice', 'z_level', 'z_mm', 'level']:
    if key in d:
        print(d[key])
        break
" 2>/dev/null || echo "")
        break
    fi
done

# Check for measurement markup files
CAUDATE_MARKUP_EXISTS="false"
RIGHTLOBE_MARKUP_EXISTS="false"

CAUDATE_PATHS=(
    "$IRCADB_DIR/caudate_measurement.mrk.json"
    "$IRCADB_DIR/caudate.mrk.json"
)

for path in "${CAUDATE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CAUDATE_MARKUP_EXISTS="true"
        # Try to extract length if not found in report
        if [ -z "$AGENT_CAUDATE" ]; then
            AGENT_CAUDATE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('length_mm', ''))" 2>/dev/null || echo "")
        fi
        break
    fi
done

RIGHTLOBE_PATHS=(
    "$IRCADB_DIR/rightlobe_measurement.mrk.json"
    "$IRCADB_DIR/right_lobe_measurement.mrk.json"
    "$IRCADB_DIR/rightlobe.mrk.json"
)

for path in "${RIGHTLOBE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        RIGHTLOBE_MARKUP_EXISTS="true"
        if [ -z "$AGENT_RIGHTLOBE" ]; then
            AGENT_RIGHTLOBE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('length_mm', ''))" 2>/dev/null || echo "")
        fi
        break
    fi
done

# Load ground truth
GT_PATH="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_crl_gt.json"
GT_CAUDATE=""
GT_RIGHTLOBE=""
GT_RATIO=""
GT_CLASSIFICATION=""
GT_SLICE=""

if [ -f "$GT_PATH" ]; then
    GT_CAUDATE=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('caudate_width_mm', 0))" 2>/dev/null || echo "0")
    GT_RIGHTLOBE=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('rightlobe_width_mm', 0))" 2>/dev/null || echo "0")
    GT_RATIO=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('crl_ratio', 0))" 2>/dev/null || echo "0")
    GT_CLASSIFICATION=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('classification', 'unknown'))" 2>/dev/null || echo "unknown")
    GT_SLICE=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('bifurcation_z_mm', 0))" 2>/dev/null || echo "0")
fi

# Check screenshot
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/crl_final.png" ]; then
    SIZE=$(stat -c %s "/tmp/crl_final.png" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 10000 ]; then
        SCREENSHOT_EXISTS="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "caudate_markup_exists": $CAUDATE_MARKUP_EXISTS,
    "rightlobe_markup_exists": $RIGHTLOBE_MARKUP_EXISTS,
    "agent_caudate_mm": "$AGENT_CAUDATE",
    "agent_rightlobe_mm": "$AGENT_RIGHTLOBE",
    "agent_ratio": "$AGENT_RATIO",
    "agent_classification": "$AGENT_CLASSIFICATION",
    "agent_slice_mm": "$AGENT_SLICE",
    "gt_caudate_mm": "$GT_CAUDATE",
    "gt_rightlobe_mm": "$GT_RIGHTLOBE",
    "gt_ratio": "$GT_RATIO",
    "gt_classification": "$GT_CLASSIFICATION",
    "gt_slice_mm": "$GT_SLICE",
    "patient_num": "$PATIENT_NUM",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to accessible location
rm -f /tmp/crl_task_result.json 2>/dev/null || sudo rm -f /tmp/crl_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crl_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crl_task_result.json
chmod 666 /tmp/crl_task_result.json 2>/dev/null || sudo chmod 666 /tmp/crl_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/crl_task_result.json
echo ""
echo "=== Export Complete ==="