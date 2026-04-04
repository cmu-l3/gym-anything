#!/bin/bash
echo "=== Exporting Create Hollow Shell Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
fi

echo "Slicer running: $SLICER_RUNNING"

# Get original volume
ORIGINAL_VOLUME_ML="0"
if [ -f /tmp/original_liver_volume.txt ]; then
    ORIGINAL_VOLUME_ML=$(cat /tmp/original_liver_volume.txt)
fi
echo "Original volume: $ORIGINAL_VOLUME_ML mL"

# Create Python script to extract current segment statistics
cat > /tmp/export_hollow_result.py << 'PYEOF'
import slicer
import os
import json
import time

print("=== Exporting Hollow Shell Results ===")

result = {
    "segment_exists": False,
    "segment_name": "",
    "final_volume_ml": 0,
    "final_volume_mm3": 0,
    "original_volume_ml": 0,
    "volume_reduction_percent": 0,
    "num_segments": 0,
    "segmentation_found": False,
    "hollow_applied": False,
    "timestamp": time.time()
}

# Load original volume
try:
    with open("/tmp/original_liver_volume.txt", "r") as f:
        result["original_volume_ml"] = float(f.read().strip())
except:
    pass

# Find segmentation node
segmentationNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(segmentationNodes)} segmentation node(s)")

for segNode in segmentationNodes:
    segmentation = segNode.GetSegmentation()
    if not segmentation:
        continue
    
    result["segmentation_found"] = True
    result["num_segments"] = segmentation.GetNumberOfSegments()
    print(f"Segmentation: {segNode.GetName()}, segments: {result['num_segments']}")
    
    # Look for Liver segment
    for i in range(segmentation.GetNumberOfSegments()):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment_name = segment.GetName() if segment else ""
        
        print(f"  Segment {i}: {segment_name}")
        
        if "Liver" in segment_name or "liver" in segment_name.lower():
            result["segment_exists"] = True
            result["segment_name"] = segment_name
            
            # Calculate current volume using SegmentStatistics
            import SegmentStatistics
            segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
            segStatLogic.getParameterNode().SetParameter("Segmentation", segNode.GetID())
            segStatLogic.computeStatistics()
            stats = segStatLogic.getStatistics()
            
            vol_key = f"{segment_id},LabelmapSegmentStatisticsPlugin.volume_mm3"
            if vol_key in stats:
                result["final_volume_mm3"] = stats[vol_key]
                result["final_volume_ml"] = result["final_volume_mm3"] / 1000.0
                print(f"  Current volume: {result['final_volume_ml']:.2f} mL")
            
            # Calculate volume reduction
            if result["original_volume_ml"] > 0 and result["final_volume_ml"] > 0:
                reduction = (result["original_volume_ml"] - result["final_volume_ml"]) / result["original_volume_ml"]
                result["volume_reduction_percent"] = reduction * 100
                print(f"  Volume reduction: {result['volume_reduction_percent']:.1f}%")
                
                # Determine if hollow was applied (significant volume reduction)
                if reduction > 0.2:
                    result["hollow_applied"] = True
            
            break
    
    if result["segment_exists"]:
        break

# Save result
result_path = "/tmp/hollow_shell_result.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result saved to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

# Run the export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Running export script in Slicer..."
    
    # Execute Python script in running Slicer instance
    # Method 1: Try using Slicer's --python-code option with running instance
    # Method 2: Use xdotool to interact with Slicer Python console
    
    # Try running a new Slicer instance with --no-main-window to query the scene
    # Note: This won't work if scene isn't saved. Instead, we use xdotool.
    
    # Focus Slicer window
    DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
    sleep 1
    
    # Open Python console (Ctrl+3) and run script
    DISPLAY=:1 xdotool key ctrl+3
    sleep 2
    
    # Type the export commands
    DISPLAY=:1 xdotool type --delay 20 'exec(open("/tmp/export_hollow_result.py").read())'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 5
    
    # Close Python console
    DISPLAY=:1 xdotool key ctrl+3
    sleep 1
fi

# Wait for result file
echo "Waiting for result file..."
for i in {1..20}; do
    if [ -f /tmp/hollow_shell_result.json ]; then
        echo "Result file found"
        break
    fi
    sleep 1
done

# If result file not created, create a minimal one
if [ ! -f /tmp/hollow_shell_result.json ]; then
    echo "Creating fallback result file..."
    
    # Try alternative: launch headless Slicer to query scene
    # This requires scene to be auto-saved or we estimate from screenshots
    
    cat > /tmp/hollow_shell_result.json << EOF
{
    "segment_exists": false,
    "segment_name": "",
    "final_volume_ml": 0,
    "original_volume_ml": $ORIGINAL_VOLUME_ML,
    "volume_reduction_percent": 0,
    "segmentation_found": false,
    "hollow_applied": false,
    "fallback": true,
    "slicer_was_running": $SLICER_RUNNING
}
EOF
fi

# Read the result
RESULT=$(cat /tmp/hollow_shell_result.json 2>/dev/null || echo "{}")

# Extract values
SEGMENT_EXISTS=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('segment_exists', False)).lower())" 2>/dev/null || echo "false")
FINAL_VOLUME=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('final_volume_ml', 0))" 2>/dev/null || echo "0")
VOLUME_REDUCTION=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('volume_reduction_percent', 0))" 2>/dev/null || echo "0")
HOLLOW_APPLIED=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('hollow_applied', False)).lower())" 2>/dev/null || echo "false")

echo ""
echo "Results:"
echo "  Segment exists: $SEGMENT_EXISTS"
echo "  Original volume: $ORIGINAL_VOLUME_ML mL"
echo "  Final volume: $FINAL_VOLUME mL"
echo "  Volume reduction: $VOLUME_REDUCTION %"
echo "  Hollow applied: $HOLLOW_APPLIED"

# Create final comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segment_exists": $SEGMENT_EXISTS,
    "original_volume_ml": $ORIGINAL_VOLUME_ML,
    "final_volume_ml": $FINAL_VOLUME,
    "volume_reduction_percent": $VOLUME_REDUCTION,
    "hollow_applied": $HOLLOW_APPLIED,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "initial_screenshot_exists": $([ -f /tmp/task_initial.png ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/hollow_task_final_result.json 2>/dev/null || sudo rm -f /tmp/hollow_task_final_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hollow_task_final_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hollow_task_final_result.json
chmod 666 /tmp/hollow_task_final_result.json 2>/dev/null || sudo chmod 666 /tmp/hollow_task_final_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Final result saved to /tmp/hollow_task_final_result.json"
cat /tmp/hollow_task_final_result.json

echo ""
echo "=== Export Complete ==="