#!/bin/bash
echo "=== Exporting Merge Tumor Segments Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
SAMPLE_ID=$(cat /tmp/merge_segments_sample_id 2>/dev/null || echo "BraTS2021_00000")
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/merge_segments_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create Python script to extract segmentation state
cat > /tmp/export_segments.py << 'PYEOF'
import slicer
import json
import os
import math

output_path = "/tmp/segment_export.json"
result = {
    "segments": [],
    "total_tumor_found": False,
    "total_tumor_segment_id": None,
    "total_tumor_volume_voxels": 0,
    "original_segments_preserved": False,
    "segment_editor_module_accessed": False,
    "segmentation_node_exists": False
}

try:
    # Check for segmentation nodes
    segmentation_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    if segmentation_nodes:
        result["segmentation_node_exists"] = True
        
        for seg_node in segmentation_nodes:
            segmentation = seg_node.GetSegmentation()
            num_segments = segmentation.GetNumberOfSegments()
            
            print(f"Found segmentation '{seg_node.GetName()}' with {num_segments} segments")
            
            # Track original segments
            found_necrotic = False
            found_edema = False
            found_enhancing = False
            
            for i in range(num_segments):
                segment_id = segmentation.GetNthSegmentID(i)
                segment = segmentation.GetSegment(segment_id)
                name = segment.GetName()
                color = segment.GetColor()
                
                # Get segment statistics
                # Use segment statistics logic
                import SegmentStatistics
                segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
                segStatLogic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
                segStatLogic.getParameterNode().SetParameter("LabelmapSegmentStatisticsPlugin.enabled", "True")
                segStatLogic.computeStatistics()
                stats = segStatLogic.getStatistics()
                
                voxel_count = 0
                volume_mm3 = 0
                for stat_key in stats.keys():
                    if segment_id in stat_key:
                        if "voxel_count" in stat_key.lower():
                            voxel_count = stats[stat_key]
                        elif "volume_mm3" in stat_key.lower():
                            volume_mm3 = stats[stat_key]
                
                segment_info = {
                    "name": name,
                    "segment_id": segment_id,
                    "color": list(color),
                    "voxel_count": int(voxel_count) if voxel_count else 0,
                    "volume_mm3": float(volume_mm3) if volume_mm3 else 0
                }
                result["segments"].append(segment_info)
                print(f"  Segment: {name}, voxels: {voxel_count}")
                
                # Check for original segments
                name_lower = name.lower()
                if "necrotic" in name_lower or "ncr" in name_lower:
                    found_necrotic = True
                if "edema" in name_lower or "ed" in name_lower:
                    found_edema = True
                if "enhancing" in name_lower or "et" in name_lower:
                    found_enhancing = True
                
                # Check for Total Tumor segment
                if "total" in name_lower and "tumor" in name_lower:
                    result["total_tumor_found"] = True
                    result["total_tumor_segment_id"] = segment_id
                    result["total_tumor_volume_voxels"] = int(voxel_count) if voxel_count else 0
                    result["total_tumor_name"] = name
                    print(f"  *** Found Total Tumor segment: {name}")
            
            result["original_segments_preserved"] = found_necrotic and found_edema and found_enhancing
            result["found_necrotic"] = found_necrotic
            result["found_edema"] = found_edema
            result["found_enhancing"] = found_enhancing
    
    # Check if Segment Editor module was used (look at module history or current module)
    try:
        currentModule = slicer.util.mainWindow().moduleSelector().selectedModule
        if "SegmentEditor" in str(currentModule):
            result["segment_editor_module_accessed"] = True
    except:
        pass
    
    result["export_success"] = True
    
except Exception as e:
    result["export_success"] = False
    result["export_error"] = str(e)
    print(f"Export error: {e}")

# Save result
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nExport saved to: {output_path}")
print(f"Total Tumor found: {result['total_tumor_found']}")
print(f"Original segments preserved: {result['original_segments_preserved']}")
PYEOF

# Run export script in Slicer if running
SEGMENT_EXPORT_SUCCESS="false"
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Running segment export in Slicer..."
    
    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_segments.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..30}; do
        if [ -f /tmp/segment_export.json ]; then
            SEGMENT_EXPORT_SUCCESS="true"
            break
        fi
        sleep 1
    done
    
    # Kill export process if still running
    kill $EXPORT_PID 2>/dev/null || true
fi

# Load export results
TOTAL_TUMOR_FOUND="false"
TOTAL_TUMOR_NAME=""
TOTAL_TUMOR_VOXELS=0
ORIGINAL_PRESERVED="false"
NUM_SEGMENTS=0
FOUND_NECROTIC="false"
FOUND_EDEMA="false"
FOUND_ENHANCING="false"

if [ -f /tmp/segment_export.json ]; then
    echo "Reading segment export..."
    TOTAL_TUMOR_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/segment_export.json')).get('total_tumor_found', False) else 'false')" 2>/dev/null || echo "false")
    TOTAL_TUMOR_NAME=$(python3 -c "import json; print(json.load(open('/tmp/segment_export.json')).get('total_tumor_name', ''))" 2>/dev/null || echo "")
    TOTAL_TUMOR_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/segment_export.json')).get('total_tumor_volume_voxels', 0))" 2>/dev/null || echo "0")
    ORIGINAL_PRESERVED=$(python3 -c "import json; print('true' if json.load(open('/tmp/segment_export.json')).get('original_segments_preserved', False) else 'false')" 2>/dev/null || echo "false")
    NUM_SEGMENTS=$(python3 -c "import json; print(len(json.load(open('/tmp/segment_export.json')).get('segments', [])))" 2>/dev/null || echo "0")
    FOUND_NECROTIC=$(python3 -c "import json; print('true' if json.load(open('/tmp/segment_export.json')).get('found_necrotic', False) else 'false')" 2>/dev/null || echo "false")
    FOUND_EDEMA=$(python3 -c "import json; print('true' if json.load(open('/tmp/segment_export.json')).get('found_edema', False) else 'false')" 2>/dev/null || echo "false")
    FOUND_ENHANCING=$(python3 -c "import json; print('true' if json.load(open('/tmp/segment_export.json')).get('found_enhancing', False) else 'false')" 2>/dev/null || echo "false")
fi

# Load initial stats for comparison
EXPECTED_TOTAL_VOXELS=0
INITIAL_STATS_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_initial_stats.json"
if [ -f "$INITIAL_STATS_FILE" ]; then
    EXPECTED_TOTAL_VOXELS=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('expected_merged_voxels', 0))" 2>/dev/null || echo "0")
fi

# Calculate volume consistency
VOLUME_CONSISTENT="false"
VOLUME_DIFF_PERCENT=100
if [ "$TOTAL_TUMOR_VOXELS" -gt 0 ] && [ "$EXPECTED_TOTAL_VOXELS" -gt 0 ]; then
    VOLUME_DIFF_PERCENT=$(python3 -c "
actual = $TOTAL_TUMOR_VOXELS
expected = $EXPECTED_TOTAL_VOXELS
diff_pct = abs(actual - expected) / expected * 100
print(f'{diff_pct:.1f}')
" 2>/dev/null || echo "100")
    
    if python3 -c "exit(0 if abs($TOTAL_TUMOR_VOXELS - $EXPECTED_TOTAL_VOXELS) / $EXPECTED_TOTAL_VOXELS <= 0.10 else 1)" 2>/dev/null; then
        VOLUME_CONSISTENT="true"
    fi
fi

# Check name format
CORRECT_NAME_FORMAT="false"
if echo "$TOTAL_TUMOR_NAME" | grep -qiE "^total[_ ]?tumor$"; then
    CORRECT_NAME_FORMAT="true"
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segment_export_success": $SEGMENT_EXPORT_SUCCESS,
    "total_tumor_found": $TOTAL_TUMOR_FOUND,
    "total_tumor_name": "$TOTAL_TUMOR_NAME",
    "total_tumor_voxels": $TOTAL_TUMOR_VOXELS,
    "expected_total_voxels": $EXPECTED_TOTAL_VOXELS,
    "volume_consistent": $VOLUME_CONSISTENT,
    "volume_diff_percent": $VOLUME_DIFF_PERCENT,
    "correct_name_format": $CORRECT_NAME_FORMAT,
    "original_segments_preserved": $ORIGINAL_PRESERVED,
    "found_necrotic": $FOUND_NECROTIC,
    "found_edema": $FOUND_EDEMA,
    "found_enhancing": $FOUND_ENHANCING,
    "num_segments": $NUM_SEGMENTS,
    "sample_id": "$SAMPLE_ID",
    "screenshot_path": "/tmp/merge_segments_final.png"
}
EOF

# Move to final location
rm -f /tmp/merge_segments_result.json 2>/dev/null || sudo rm -f /tmp/merge_segments_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/merge_segments_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/merge_segments_result.json
chmod 666 /tmp/merge_segments_result.json 2>/dev/null || sudo chmod 666 /tmp/merge_segments_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/merge_segments_result.json"
cat /tmp/merge_segments_result.json
echo ""
echo "=== Export Complete ==="
echo "Total Tumor Found: $TOTAL_TUMOR_FOUND"
echo "Total Tumor Name: $TOTAL_TUMOR_NAME"
echo "Volume Consistent: $VOLUME_CONSISTENT (diff: ${VOLUME_DIFF_PERCENT}%)"
echo "Original Segments Preserved: $ORIGINAL_PRESERVED"