#!/bin/bash
echo "=== Exporting Dose Zone Margins Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/dose_zones.seg.nrrd"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/dose_zone_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Try to export segmentation data from Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting segment information from Slicer..."
    
    cat > /tmp/export_dose_zones.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
result_path = "/tmp/dose_zone_segments.json"

result = {
    "segments": [],
    "segment_count": 0,
    "segmentation_node_exists": False,
    "errors": []
}

try:
    # Find segmentation nodes
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    if not seg_nodes:
        result["errors"].append("No segmentation node found")
    else:
        # Use the first segmentation node (should be DoseZones)
        seg_node = None
        for node in seg_nodes:
            if "zone" in node.GetName().lower() or "dose" in node.GetName().lower():
                seg_node = node
                break
        if not seg_node:
            seg_node = seg_nodes[0]
        
        result["segmentation_node_exists"] = True
        result["segmentation_name"] = seg_node.GetName()
        
        segmentation = seg_node.GetSegmentation()
        num_segments = segmentation.GetNumberOfSegments()
        result["segment_count"] = num_segments
        
        print(f"Found {num_segments} segments in '{seg_node.GetName()}'")
        
        # Get segment statistics
        import SegmentStatistics
        stats_logic = SegmentStatistics.SegmentStatisticsLogic()
        stats_logic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
        
        # Get reference volume
        vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        if vol_nodes:
            stats_logic.getParameterNode().SetParameter("ScalarVolume", vol_nodes[0].GetID())
        
        stats_logic.computeStatistics()
        stats = stats_logic.getStatistics()
        
        # Extract info for each segment
        for i in range(num_segments):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            
            name = segment.GetName()
            color = list(segment.GetColor())
            color_rgb = [int(c * 255) for c in color]
            
            # Get volume from statistics
            volume_mm3 = 0
            volume_key = f"{segment_id}.LabelmapSegmentStatisticsPlugin.volume_mm3"
            if volume_key in stats:
                volume_mm3 = stats[volume_key]
            
            seg_info = {
                "id": segment_id,
                "name": name,
                "color_normalized": color,
                "color_rgb": color_rgb,
                "volume_mm3": volume_mm3,
                "volume_ml": volume_mm3 / 1000.0 if volume_mm3 else 0
            }
            
            result["segments"].append(seg_info)
            print(f"  Segment '{name}': color={color_rgb}, volume={volume_mm3:.0f} mm³")
        
        # Try to save the segmentation
        seg_path = os.path.join(output_dir, "dose_zones.seg.nrrd")
        try:
            slicer.util.saveNode(seg_node, seg_path)
            result["segmentation_saved"] = True
            result["segmentation_path"] = seg_path
            print(f"Segmentation saved to: {seg_path}")
        except Exception as e:
            result["errors"].append(f"Failed to save segmentation: {e}")
            result["segmentation_saved"] = False

except Exception as e:
    result["errors"].append(f"Export error: {str(e)}")
    import traceback
    result["traceback"] = traceback.format_exc()

# Save result
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Segment data exported to: {result_path}")
PYEOF

    # Run export script in Slicer (non-blocking with timeout)
    timeout 30 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/export_dose_zones.py" > /tmp/export_slicer.log 2>&1 || true
    sleep 5
fi

# Read exported segment data
SEGMENT_DATA_FILE="/tmp/dose_zone_segments.json"
SEGMENT_COUNT=0
SEGMENTATION_EXISTS="false"
SEGMENTS_JSON="[]"

if [ -f "$SEGMENT_DATA_FILE" ]; then
    SEGMENT_COUNT=$(python3 -c "import json; print(json.load(open('$SEGMENT_DATA_FILE')).get('segment_count', 0))" 2>/dev/null || echo "0")
    SEGMENTATION_EXISTS=$(python3 -c "import json; print('true' if json.load(open('$SEGMENT_DATA_FILE')).get('segmentation_node_exists', False) else 'false')" 2>/dev/null || echo "false")
    SEGMENTS_JSON=$(python3 -c "import json; print(json.dumps(json.load(open('$SEGMENT_DATA_FILE')).get('segments', [])))" 2>/dev/null || echo "[]")
fi

# Check if output segmentation file was created
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SEG" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SEG" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SEG" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Also check for alternative output paths
ALT_OUTPUTS=(
    "$BRATS_DIR/dose_zones.nrrd"
    "$BRATS_DIR/DoseZones.seg.nrrd"
    "$BRATS_DIR/segmentation.seg.nrrd"
)

for alt_path in "${ALT_OUTPUTS[@]}"; do
    if [ -f "$alt_path" ] && [ "$OUTPUT_EXISTS" = "false" ]; then
        OUTPUT_EXISTS="true"
        OUTPUT_SIZE=$(stat -c %s "$alt_path" 2>/dev/null || echo "0")
        OUTPUT_MTIME=$(stat -c %Y "$alt_path" 2>/dev/null || echo "0")
        OUTPUT_SEG="$alt_path"
        
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        
        echo "Found alternative output at: $alt_path"
        break
    fi
done

# Load initial tumor stats for reference
INITIAL_TUMOR_VOLUME=0
if [ -f "/tmp/initial_tumor_stats.json" ]; then
    INITIAL_TUMOR_VOLUME=$(python3 -c "import json; print(json.load(open('/tmp/initial_tumor_stats.json')).get('tumor_volume_mm3', 0))" 2>/dev/null || echo "0")
fi

# Analyze segments to check for zone characteristics
echo "Analyzing segment properties..."
python3 << PYEOF
import json
import os

segment_file = "$SEGMENT_DATA_FILE"
analysis_file = "/tmp/dose_zone_analysis.json"

analysis = {
    "zone1_found": False,
    "zone2_found": False,
    "zone3_found": False,
    "tumor_found": False,
    "zone1_color_correct": False,
    "zone2_color_correct": False,
    "zone3_color_correct": False,
    "volume_ordering_correct": False,
    "zones_are_rings": False,
    "zone_details": {}
}

def color_matches(rgb, target, tolerance=30):
    """Check if RGB color matches target within tolerance"""
    return all(abs(a - b) <= tolerance for a, b in zip(rgb, target))

if os.path.exists(segment_file):
    with open(segment_file) as f:
        data = json.load(f)
    
    segments = data.get("segments", [])
    
    zone1_volume = 0
    zone2_volume = 0
    zone3_volume = 0
    tumor_volume = 0
    
    for seg in segments:
        name = seg.get("name", "").lower()
        color = seg.get("color_rgb", [0, 0, 0])
        volume = seg.get("volume_mm3", 0)
        
        # Check for tumor segment
        if "tumor" in name and "zone" not in name:
            analysis["tumor_found"] = True
            tumor_volume = volume
            analysis["zone_details"]["tumor"] = {"volume_mm3": volume, "color": color}
        
        # Check for Zone 1 (5mm, red)
        if ("zone1" in name or "zone_1" in name or "5mm" in name) and ("10" not in name and "15" not in name):
            analysis["zone1_found"] = True
            zone1_volume = volume
            # Red: (255, 0, 0)
            if color_matches(color, [255, 0, 0], 30):
                analysis["zone1_color_correct"] = True
            analysis["zone_details"]["zone1"] = {"volume_mm3": volume, "color": color, "color_correct": analysis["zone1_color_correct"]}
        
        # Check for Zone 2 (10mm, yellow)
        if ("zone2" in name or "zone_2" in name or "10mm" in name) and "15" not in name:
            analysis["zone2_found"] = True
            zone2_volume = volume
            # Yellow: (255, 255, 0)
            if color_matches(color, [255, 255, 0], 30):
                analysis["zone2_color_correct"] = True
            analysis["zone_details"]["zone2"] = {"volume_mm3": volume, "color": color, "color_correct": analysis["zone2_color_correct"]}
        
        # Check for Zone 3 (15mm, green)
        if "zone3" in name or "zone_3" in name or "15mm" in name:
            analysis["zone3_found"] = True
            zone3_volume = volume
            # Green: (0, 255, 0)
            if color_matches(color, [0, 255, 0], 30):
                analysis["zone3_color_correct"] = True
            analysis["zone_details"]["zone3"] = {"volume_mm3": volume, "color": color, "color_correct": analysis["zone3_color_correct"]}
    
    # Check volume ordering (outer rings should have larger volume)
    if zone1_volume > 0 and zone2_volume > 0 and zone3_volume > 0:
        if zone1_volume < zone2_volume < zone3_volume:
            analysis["volume_ordering_correct"] = True
        
        # Check if they're rings (not solid spheres)
        # For rings: zone1 < zone2 < zone3, and none should be dramatically larger
        # A solid 15mm sphere would be ~3x larger than a 5mm sphere
        # Rings should have more similar volumes
        if zone3_volume < zone1_volume * 5:  # Reasonable ratio for rings
            analysis["zones_are_rings"] = True
    
    analysis["volumes"] = {
        "tumor": tumor_volume,
        "zone1": zone1_volume,
        "zone2": zone2_volume,
        "zone3": zone3_volume
    }

with open(analysis_file, "w") as f:
    json.dump(analysis, f, indent=2)

print(f"Analysis saved to: {analysis_file}")
PYEOF

# Read analysis results
ANALYSIS_FILE="/tmp/dose_zone_analysis.json"
ZONE1_FOUND="false"
ZONE2_FOUND="false"
ZONE3_FOUND="false"
TUMOR_FOUND="false"
ZONE1_COLOR_OK="false"
ZONE2_COLOR_OK="false"
ZONE3_COLOR_OK="false"
VOLUME_ORDER_OK="false"
ZONES_ARE_RINGS="false"

if [ -f "$ANALYSIS_FILE" ]; then
    ZONE1_FOUND=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone1_found') else 'false')" 2>/dev/null || echo "false")
    ZONE2_FOUND=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone2_found') else 'false')" 2>/dev/null || echo "false")
    ZONE3_FOUND=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone3_found') else 'false')" 2>/dev/null || echo "false")
    TUMOR_FOUND=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('tumor_found') else 'false')" 2>/dev/null || echo "false")
    ZONE1_COLOR_OK=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone1_color_correct') else 'false')" 2>/dev/null || echo "false")
    ZONE2_COLOR_OK=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone2_color_correct') else 'false')" 2>/dev/null || echo "false")
    ZONE3_COLOR_OK=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zone3_color_correct') else 'false')" 2>/dev/null || echo "false")
    VOLUME_ORDER_OK=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('volume_ordering_correct') else 'false')" 2>/dev/null || echo "false")
    ZONES_ARE_RINGS=$(python3 -c "import json; print('true' if json.load(open('$ANALYSIS_FILE')).get('zones_are_rings') else 'false')" 2>/dev/null || echo "false")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_node_exists": $SEGMENTATION_EXISTS,
    "segment_count": $SEGMENT_COUNT,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "tumor_found": $TUMOR_FOUND,
    "zone1_found": $ZONE1_FOUND,
    "zone2_found": $ZONE2_FOUND,
    "zone3_found": $ZONE3_FOUND,
    "zone1_color_correct": $ZONE1_COLOR_OK,
    "zone2_color_correct": $ZONE2_COLOR_OK,
    "zone3_color_correct": $ZONE3_COLOR_OK,
    "volume_ordering_correct": $VOLUME_ORDER_OK,
    "zones_are_rings": $ZONES_ARE_RINGS,
    "initial_tumor_volume_mm3": $INITIAL_TUMOR_VOLUME,
    "segments": $SEGMENTS_JSON,
    "screenshot_path": "/tmp/dose_zone_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/dose_zone_result.json 2>/dev/null || sudo rm -f /tmp/dose_zone_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dose_zone_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dose_zone_result.json
chmod 666 /tmp/dose_zone_result.json 2>/dev/null || sudo chmod 666 /tmp/dose_zone_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy analysis file for verifier
cp "$ANALYSIS_FILE" /tmp/dose_zone_analysis_export.json 2>/dev/null || true
chmod 666 /tmp/dose_zone_analysis_export.json 2>/dev/null || true

echo ""
echo "=== Export Results ==="
echo "Result saved to: /tmp/dose_zone_result.json"
cat /tmp/dose_zone_result.json
echo ""
echo "=== Export Complete ==="