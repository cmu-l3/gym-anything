#!/bin/bash
echo "=== Exporting Brain Parenchymal Fraction Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# -------------------------------------------------------
# 1. Record task end time
# -------------------------------------------------------
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# -------------------------------------------------------
# 2. Take final screenshot
# -------------------------------------------------------
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# -------------------------------------------------------
# 3. Search for segmentation output file
# -------------------------------------------------------
OUTPUT_DIR="/home/ga/Documents/SlicerData/BrainAssessment"
MRI_PATH="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

SEG_FILE_EXISTS="false"
SEG_FILE_PATH=""
SEG_FILE_SIZE=0
SEG_FILE_MTIME=0

# Check expected and alternative paths
SEARCH_PATHS=(
    "$OUTPUT_DIR/brain_bpf.seg.nrrd"
    "$OUTPUT_DIR/brain_structures.seg.nrrd"
    "$OUTPUT_DIR/Segmentation.seg.nrrd"
    "$OUTPUT_DIR/brain_segmentation.seg.nrrd"
    "/home/ga/Documents/SlicerData/Exports/brain_bpf.seg.nrrd"
    "/home/ga/Documents/SlicerData/Exports/Segmentation.seg.nrrd"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_FILE_EXISTS="true"
        SEG_FILE_PATH="$path"
        SEG_FILE_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        SEG_FILE_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        echo "Found segmentation file: $path (${SEG_FILE_SIZE} bytes)"
        break
    fi
done

# Fallback: search for any .seg.nrrd created during task
if [ "$SEG_FILE_EXISTS" = "false" ]; then
    for search_dir in "$OUTPUT_DIR" "/home/ga/Documents/SlicerData/Exports" "/home/ga/Documents" "/home/ga"; do
        NEW_SEG=$(find "$search_dir" -maxdepth 2 -name "*.seg.nrrd" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
        if [ -n "$NEW_SEG" ] && [ -f "$NEW_SEG" ]; then
            SEG_FILE_EXISTS="true"
            SEG_FILE_PATH="$NEW_SEG"
            SEG_FILE_SIZE=$(stat -c%s "$NEW_SEG" 2>/dev/null || echo "0")
            SEG_FILE_MTIME=$(stat -c%Y "$NEW_SEG" 2>/dev/null || echo "0")
            echo "Found new segmentation file: $NEW_SEG"
            break
        fi
    done
fi

# Anti-gaming: check if file was created during task
SEG_CREATED_DURING_TASK="false"
if [ "$SEG_FILE_EXISTS" = "true" ] && [ "$SEG_FILE_MTIME" -gt "$TASK_START" ]; then
    SEG_CREATED_DURING_TASK="true"
fi

# -------------------------------------------------------
# 4. Search for report JSON
# -------------------------------------------------------
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_CONTENT=""

REPORT_SEARCH_PATHS=(
    "$OUTPUT_DIR/bpf_report.json"
    "$OUTPUT_DIR/morphometry_report.json"
    "$OUTPUT_DIR/report.json"
    "$OUTPUT_DIR/brain_report.json"
    "/home/ga/Documents/SlicerData/Exports/bpf_report.json"
)

for path in "${REPORT_SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_CONTENT=$(cat "$path" 2>/dev/null | head -c 4096)
        echo "Found report: $path"
        break
    fi
done

# Fallback: search for any .json report created during task
if [ "$REPORT_EXISTS" = "false" ]; then
    for search_dir in "$OUTPUT_DIR" "/home/ga/Documents/SlicerData/Exports" "/home/ga/Documents"; do
        NEW_RPT=$(find "$search_dir" -maxdepth 2 -name "*report*.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
        if [ -z "$NEW_RPT" ]; then
            NEW_RPT=$(find "$search_dir" -maxdepth 2 -name "*bpf*.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
        fi
        if [ -n "$NEW_RPT" ] && [ -f "$NEW_RPT" ]; then
            REPORT_EXISTS="true"
            REPORT_PATH="$NEW_RPT"
            REPORT_CONTENT=$(cat "$NEW_RPT" 2>/dev/null | head -c 4096)
            echo "Found report: $NEW_RPT"
            break
        fi
    done
fi

# -------------------------------------------------------
# 5. Search for 3D screenshot
# -------------------------------------------------------
SCREENSHOT_3D_EXISTS="false"
SCREENSHOT_3D_PATH=""
SCREENSHOT_3D_SIZE=0

SCREENSHOT_SEARCH_PATHS=(
    "$OUTPUT_DIR/brain_3d.png"
    "$OUTPUT_DIR/3d_rendering.png"
    "$OUTPUT_DIR/screenshot.png"
)

for path in "${SCREENSHOT_SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_3D_EXISTS="true"
        SCREENSHOT_3D_PATH="$path"
        SCREENSHOT_3D_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        echo "Found 3D screenshot: $path (${SCREENSHOT_3D_SIZE} bytes)"
        break
    fi
done

# Fallback: any PNG in output dir created during task
if [ "$SCREENSHOT_3D_EXISTS" = "false" ]; then
    NEW_PNG=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEW_PNG" ] && [ -f "$NEW_PNG" ]; then
        SCREENSHOT_3D_EXISTS="true"
        SCREENSHOT_3D_PATH="$NEW_PNG"
        SCREENSHOT_3D_SIZE=$(stat -c%s "$NEW_PNG" 2>/dev/null || echo "0")
        echo "Found screenshot: $NEW_PNG"
    fi
fi

# Also check Slicer's default screenshot directory
if [ "$SCREENSHOT_3D_EXISTS" = "false" ]; then
    NEW_PNG=$(find /home/ga/Documents/SlicerData/Screenshots -maxdepth 1 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEW_PNG" ] && [ -f "$NEW_PNG" ]; then
        SCREENSHOT_3D_EXISTS="true"
        SCREENSHOT_3D_PATH="$NEW_PNG"
        SCREENSHOT_3D_SIZE=$(stat -c%s "$NEW_PNG" 2>/dev/null || echo "0")
        echo "Found screenshot in Screenshots dir: $NEW_PNG"
    fi
fi

# -------------------------------------------------------
# 6. Analyze segmentation content with Python
# -------------------------------------------------------
NUM_SEGMENTS=0
SEGMENT_NAMES=""
CEREBRUM_VOXELS=0
VENTRICLE_VOXELS=0
CEREBRUM_VOLUME_ML=0
VENTRICLE_VOLUME_ML=0
ANALYSIS_ERROR=""

if [ "$SEG_FILE_EXISTS" = "true" ]; then
    echo "Analyzing segmentation content..."

    python3 << PYEOF
import json
import sys
import os
import numpy as np

try:
    import nrrd
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"])
    import nrrd

analysis = {
    "num_segments": 0,
    "segment_names": [],
    "segment_details": {},
    "cerebrum_voxels": 0,
    "ventricle_voxels": 0,
    "cerebrum_volume_ml": 0.0,
    "ventricle_volume_ml": 0.0,
    "total_voxels": 0,
    "error": None
}

seg_path = "$SEG_FILE_PATH"

try:
    print(f"Loading segmentation from {seg_path}")
    seg_data, header = nrrd.read(seg_path)
    print(f"Segmentation shape: {seg_data.shape}")

    # Get voxel volume from space directions
    voxel_vol_mm3 = 1.0
    dirs = header.get("space directions")
    if dirs is not None:
        voxel_sizes = [np.linalg.norm(d) for d in dirs if not any(np.isnan(d))]
        if len(voxel_sizes) >= 3:
            voxel_vol_mm3 = float(np.prod(voxel_sizes[:3]))
    print(f"Voxel volume: {voxel_vol_mm3:.4f} mm^3")

    # Count unique labels (excluding 0 = background)
    unique_labels = [int(l) for l in np.unique(seg_data) if l > 0]
    analysis["num_segments"] = len(unique_labels)
    analysis["total_voxels"] = int(np.sum(seg_data > 0))
    print(f"Found {len(unique_labels)} segments with labels: {unique_labels}")

    # Extract segment names from NRRD header (Slicer stores them as Segment*_Name)
    segment_name_map = {}
    for key, val in header.items():
        if "_Name" in key and key.startswith("Segment"):
            try:
                idx = int(key.replace("Segment", "").replace("_Name", ""))
                segment_name_map[idx] = str(val)
            except ValueError:
                pass

    # Fallback: parse raw header bytes for segment names
    if not segment_name_map:
        try:
            with open(seg_path, 'rb') as f:
                header_bytes = b''
                for line in f:
                    header_bytes += line
                    if line.strip() == b'':
                        break
                header_text = header_bytes.decode('ascii', errors='ignore')
                for line in header_text.split('\n'):
                    if 'Segment' in line and '_Name' in line:
                        parts = line.split(':=')
                        if len(parts) == 2:
                            key = parts[0].strip()
                            name = parts[1].strip()
                            try:
                                idx = int(key.replace('Segment', '').replace('_Name', ''))
                                segment_name_map[idx] = name
                            except ValueError:
                                pass
        except Exception as e:
            print(f"Could not parse raw header: {e}")

    analysis["segment_names"] = list(segment_name_map.values())
    print(f"Segment names: {analysis['segment_names']}")

    # Classify segments based on names and voxel counts
    cerebrum_keywords = ["cerebrum", "brain", "parenchyma", "cortex", "gray", "white"]
    ventricle_keywords = ["ventricle", "csf", "lateral"]

    for idx, label in enumerate(unique_labels):
        label_mask = seg_data == label
        voxel_count = int(np.sum(label_mask))
        volume_ml = voxel_count * voxel_vol_mm3 / 1000.0
        name = segment_name_map.get(idx, f"Segment_{label}")

        detail = {"label": label, "name": name, "voxel_count": voxel_count, "volume_ml": round(volume_ml, 2)}
        analysis["segment_details"][name] = detail

        name_lower = name.lower()
        if any(kw in name_lower for kw in cerebrum_keywords):
            analysis["cerebrum_voxels"] = voxel_count
            analysis["cerebrum_volume_ml"] = round(volume_ml, 2)
            print(f"  Cerebrum segment '{name}': {voxel_count} voxels, {volume_ml:.1f} mL")
        elif any(kw in name_lower for kw in ventricle_keywords):
            analysis["ventricle_voxels"] = voxel_count
            analysis["ventricle_volume_ml"] = round(volume_ml, 2)
            print(f"  Ventricle segment '{name}': {voxel_count} voxels, {volume_ml:.1f} mL")
        else:
            print(f"  Other segment '{name}': {voxel_count} voxels, {volume_ml:.1f} mL")

    # Heuristic fallback: largest = cerebrum, smallest = ventricles
    if analysis["cerebrum_voxels"] == 0 and len(unique_labels) >= 2:
        sorted_labels = sorted(unique_labels, key=lambda l: int(np.sum(seg_data == l)), reverse=True)
        largest_count = int(np.sum(seg_data == sorted_labels[0]))
        smallest_count = int(np.sum(seg_data == sorted_labels[-1]))
        analysis["cerebrum_voxels"] = largest_count
        analysis["cerebrum_volume_ml"] = round(largest_count * voxel_vol_mm3 / 1000.0, 2)
        analysis["ventricle_voxels"] = smallest_count
        analysis["ventricle_volume_ml"] = round(smallest_count * voxel_vol_mm3 / 1000.0, 2)
        print(f"  Heuristic: largest={largest_count} (cerebrum), smallest={smallest_count} (ventricles)")

except Exception as e:
    analysis["error"] = str(e)
    print(f"Analysis error: {e}")

with open("/tmp/bpf_analysis.json", "w") as f:
    json.dump(analysis, f, indent=2)
print(f"Analysis saved to /tmp/bpf_analysis.json")
PYEOF

    # Read analysis results
    if [ -f /tmp/bpf_analysis.json ]; then
        NUM_SEGMENTS=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json'))['num_segments'])" 2>/dev/null || echo "0")
        SEGMENT_NAMES=$(python3 -c "import json; print(','.join(json.load(open('/tmp/bpf_analysis.json')).get('segment_names', [])))" 2>/dev/null || echo "")
        CEREBRUM_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json'))['cerebrum_voxels'])" 2>/dev/null || echo "0")
        VENTRICLE_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json'))['ventricle_voxels'])" 2>/dev/null || echo "0")
        CEREBRUM_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json'))['cerebrum_volume_ml'])" 2>/dev/null || echo "0")
        VENTRICLE_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json'))['ventricle_volume_ml'])" 2>/dev/null || echo "0")
        ANALYSIS_ERROR=$(python3 -c "import json; print(json.load(open('/tmp/bpf_analysis.json')).get('error', '') or '')" 2>/dev/null || echo "")

        echo "Analysis results:"
        echo "  Segments: $NUM_SEGMENTS (names: $SEGMENT_NAMES)"
        echo "  Cerebrum: $CEREBRUM_VOXELS voxels, $CEREBRUM_VOLUME_ML mL"
        echo "  Ventricles: $VENTRICLE_VOXELS voxels, $VENTRICLE_VOLUME_ML mL"
    fi
fi

# -------------------------------------------------------
# 7. Parse report JSON for BPF values
# -------------------------------------------------------
REPORT_BPF=""
REPORT_CLASSIFICATION=""
REPORT_CEREBRUM_VOL=""
REPORT_VENTRICLE_VOL=""

if [ "$REPORT_EXISTS" = "true" ]; then
    REPORT_BPF=$(python3 -c "
import json
try:
    d = json.load(open('$REPORT_PATH'))
    # Try common key names
    for k in ['bpf', 'BPF', 'brain_parenchymal_fraction', 'parenchymal_fraction']:
        if k in d:
            print(d[k])
            break
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")

    REPORT_CLASSIFICATION=$(python3 -c "
import json
try:
    d = json.load(open('$REPORT_PATH'))
    for k in ['classification', 'Classification', 'bpf_classification', 'category']:
        if k in d:
            print(d[k])
            break
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")

    REPORT_CEREBRUM_VOL=$(python3 -c "
import json
try:
    d = json.load(open('$REPORT_PATH'))
    for k in ['cerebrum_volume_ml', 'cerebral_volume_ml', 'brain_volume_ml', 'cerebrum_volume']:
        if k in d:
            print(d[k])
            break
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")

    REPORT_VENTRICLE_VOL=$(python3 -c "
import json
try:
    d = json.load(open('$REPORT_PATH'))
    for k in ['ventricle_volume_ml', 'ventricular_volume_ml', 'ventricles_volume_ml', 'ventricle_volume']:
        if k in d:
            print(d[k])
            break
    else:
        print('')
except: print('')
" 2>/dev/null || echo "")

    echo "Report values: BPF=$REPORT_BPF, Classification=$REPORT_CLASSIFICATION"
    echo "  Cerebrum vol=$REPORT_CEREBRUM_VOL mL, Ventricle vol=$REPORT_VENTRICLE_VOL mL"
fi

# -------------------------------------------------------
# 8. Close Slicer
# -------------------------------------------------------
if [ "$SLICER_RUNNING" = "true" ]; then
    close_slicer 2>/dev/null || pkill -f "Slicer" 2>/dev/null || true
fi

# -------------------------------------------------------
# 9. Write result JSON
# -------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape report content for JSON embedding
REPORT_CONTENT_ESCAPED=$(echo "$REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,

    "segmentation_file_exists": $SEG_FILE_EXISTS,
    "segmentation_file_path": "$SEG_FILE_PATH",
    "segmentation_file_size": $SEG_FILE_SIZE,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,

    "num_segments": $NUM_SEGMENTS,
    "segment_names": "$SEGMENT_NAMES",
    "cerebrum_voxels": $CEREBRUM_VOXELS,
    "ventricle_voxels": $VENTRICLE_VOXELS,
    "cerebrum_volume_ml": $CEREBRUM_VOLUME_ML,
    "ventricle_volume_ml": $VENTRICLE_VOLUME_ML,

    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_bpf": "$REPORT_BPF",
    "report_classification": "$REPORT_CLASSIFICATION",
    "report_cerebrum_volume_ml": "$REPORT_CEREBRUM_VOL",
    "report_ventricle_volume_ml": "$REPORT_VENTRICLE_VOL",
    "report_content": $REPORT_CONTENT_ESCAPED,

    "screenshot_3d_exists": $SCREENSHOT_3D_EXISTS,
    "screenshot_3d_path": "$SCREENSHOT_3D_PATH",
    "screenshot_3d_size": $SCREENSHOT_3D_SIZE,

    "analysis_error": "$ANALYSIS_ERROR"
}
EOF

RESULT_FILE="/tmp/bpf_task_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
