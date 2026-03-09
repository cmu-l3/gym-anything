#!/bin/bash
echo "=== Exporting Import Labelmap Segments Task Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Query Slicer scene for segmentation info via Python script
# ============================================================
echo "Querying Slicer scene state..."

QUERY_RESULT=""
if [ "$SLICER_RUNNING" = "true" ]; then
    # Create a Python script to query Slicer state
    cat > /tmp/query_slicer_state.py << 'PYEOF'
import json
import sys
import os

result = {
    "segmentation_nodes": 0,
    "segment_count": 0,
    "segment_names": [],
    "segment_voxel_counts": [],
    "volume_nodes": 0,
    "labelmap_nodes": 0,
    "ct_loaded": False,
    "labelmap_loaded": False,
    "all_segments_nonempty": False,
    "error": None
}

try:
    import slicer
    
    # Count volume nodes
    vol_nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLScalarVolumeNode')
    result['volume_nodes'] = vol_nodes.GetNumberOfItems()
    
    # Check for specific volumes
    for i in range(vol_nodes.GetNumberOfItems()):
        node = vol_nodes.GetItemAsObject(i)
        name = node.GetName().lower()
        if 'ct' in name or 'volume' in name:
            result['ct_loaded'] = True
        if 'label' in name or 'combined' in name:
            result['labelmap_loaded'] = True
    
    # Count labelmap volume nodes
    labelmap_nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLLabelMapVolumeNode')
    result['labelmap_nodes'] = labelmap_nodes.GetNumberOfItems()
    if labelmap_nodes.GetNumberOfItems() > 0:
        result['labelmap_loaded'] = True
    
    # Check segmentation nodes
    seg_nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLSegmentationNode')
    result['segmentation_nodes'] = seg_nodes.GetNumberOfItems()
    
    if seg_nodes.GetNumberOfItems() > 0:
        seg_node = seg_nodes.GetItemAsObject(0)
        segmentation = seg_node.GetSegmentation()
        result['segment_count'] = segmentation.GetNumberOfSegments()
        
        all_nonempty = True
        for i in range(segmentation.GetNumberOfSegments()):
            seg_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(seg_id)
            seg_name = segment.GetName() if segment else f"Segment_{i}"
            result['segment_names'].append(seg_name)
            
            # Try to get voxel count using segment statistics
            try:
                # Use SegmentStatistics to get voxel count
                import SegmentStatistics
                segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
                segStatLogic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
                segStatLogic.computeStatistics()
                stats = segStatLogic.getStatistics()
                
                voxel_count = 0
                for stat_key in stats:
                    if seg_id in stat_key and 'voxel_count' in stat_key.lower():
                        voxel_count = stats[stat_key]
                        break
                result['segment_voxel_counts'].append(voxel_count)
                if voxel_count == 0:
                    all_nonempty = False
            except Exception as e:
                # Fallback: just record that we couldn't get voxel count
                result['segment_voxel_counts'].append(-1)
        
        result['all_segments_nonempty'] = all_nonempty

except Exception as e:
    result['error'] = str(e)

# Output result as JSON
print(json.dumps(result))
PYEOF

    # Run the query script in Slicer
    QUERY_RESULT=$(timeout 30 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/query_slicer_state.py 2>/dev/null" | tail -1)
    
    if [ -z "$QUERY_RESULT" ]; then
        echo "Slicer query returned empty, using default values"
        QUERY_RESULT='{"segmentation_nodes": 0, "segment_count": 0, "error": "Query failed"}'
    fi
else
    echo "Slicer not running, cannot query scene"
    QUERY_RESULT='{"segmentation_nodes": 0, "segment_count": 0, "error": "Slicer not running"}'
fi

echo "Query result: $QUERY_RESULT"

# Parse query result
SEGMENTATION_NODES=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('segmentation_nodes', 0))" 2>/dev/null || echo "0")
SEGMENT_COUNT=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('segment_count', 0))" 2>/dev/null || echo "0")
SEGMENT_NAMES=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(d.get('segment_names', [])))" 2>/dev/null || echo "")
VOLUME_NODES=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('volume_nodes', 0))" 2>/dev/null || echo "0")
CT_LOADED=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('ct_loaded', False) else 'false')" 2>/dev/null || echo "false")
LABELMAP_LOADED=$(echo "$QUERY_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('labelmap_loaded', False) else 'false')" 2>/dev/null || echo "false")

# ============================================================
# Check for output files
# ============================================================
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb/patient_5"

# Check if any segmentation files were saved
SEGMENTATION_FILE_EXISTS="false"
SEGMENTATION_FILE_PATH=""

for ext in ".seg.nrrd" ".nrrd" ".nii.gz" ".seg.vtm"; do
    for pattern in "segmentation" "Segmentation" "liver" "Liver"; do
        found=$(find "$IRCADB_DIR" -maxdepth 1 -name "*${pattern}*${ext}" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            SEGMENTATION_FILE_EXISTS="true"
            SEGMENTATION_FILE_PATH="$found"
            break 2
        fi
    done
done

# Check screenshot directory for new screenshots
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
NEW_SCREENSHOTS=$(find "$SCREENSHOT_DIR" -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# ============================================================
# Analyze final screenshot for visual evidence
# ============================================================
SCREENSHOT_SIZE_KB=0
SCREENSHOT_HAS_COLORS="false"
COLOR_COUNT=0

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE_KB=$(du -k /tmp/task_final.png 2>/dev/null | cut -f1 || echo "0")
    
    # Use ImageMagick to count unique colors (segmentation overlays have distinct colors)
    if command -v identify &> /dev/null; then
        COLOR_COUNT=$(identify -format "%k" /tmp/task_final.png 2>/dev/null || echo "0")
        # Segmentation overlays typically add significant color variety
        if [ "$COLOR_COUNT" -gt 1000 ]; then
            SCREENSHOT_HAS_COLORS="true"
        fi
    fi
fi

# ============================================================
# Check timing (anti-gaming)
# ============================================================
FILE_CREATED_DURING_TASK="false"
if [ "$SEGMENTATION_FILE_EXISTS" = "true" ] && [ -n "$SEGMENTATION_FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$SEGMENTATION_FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "volume_nodes_count": $VOLUME_NODES,
    "ct_loaded": $CT_LOADED,
    "labelmap_loaded": $LABELMAP_LOADED,
    "segmentation_nodes_count": $SEGMENTATION_NODES,
    "segment_count": $SEGMENT_COUNT,
    "segment_names": "$SEGMENT_NAMES",
    "segmentation_file_exists": $SEGMENTATION_FILE_EXISTS,
    "segmentation_file_path": "$SEGMENTATION_FILE_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_color_count": $COLOR_COUNT,
    "screenshot_has_colors": $SCREENSHOT_HAS_COLORS,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "query_result": $QUERY_RESULT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/labelmap_task_result.json 2>/dev/null || sudo rm -f /tmp/labelmap_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/labelmap_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/labelmap_task_result.json
chmod 666 /tmp/labelmap_task_result.json 2>/dev/null || sudo chmod 666 /tmp/labelmap_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "Slicer running: $SLICER_RUNNING"
echo "Volume nodes: $VOLUME_NODES"
echo "CT loaded: $CT_LOADED"
echo "Labelmap loaded: $LABELMAP_LOADED"
echo "Segmentation nodes: $SEGMENTATION_NODES"
echo "Segment count: $SEGMENT_COUNT"
echo "Segment names: $SEGMENT_NAMES"
echo ""
echo "Result saved to /tmp/labelmap_task_result.json"
cat /tmp/labelmap_task_result.json
echo ""
echo "=== Export Complete ==="