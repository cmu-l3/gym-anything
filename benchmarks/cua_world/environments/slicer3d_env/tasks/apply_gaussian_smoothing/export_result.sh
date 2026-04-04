#!/bin/bash
echo "=== Exporting Gaussian Smoothing Task Results ==="

source /workspace/scripts/task_utils.sh

RESULT_DIR="/tmp/slicer_task_results"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"

mkdir -p "$RESULT_DIR"
mkdir -p "$EXPORT_DIR"
chmod 777 "$RESULT_DIR" "$EXPORT_DIR"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
    cp /tmp/task_final.png "$SCREENSHOT_DIR/task_final.png" 2>/dev/null || true
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
else
    echo "WARNING: Slicer is not running"
fi

# ============================================================
# Export scene information via Slicer Python
# ============================================================
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer scene for volumes..."
    
    # Create Python script to extract volume information
    cat > /tmp/extract_smoothing_result.py << 'PYEOF'
import slicer
import json
import numpy as np
import os
import sys

# Ensure scipy is available
try:
    from scipy.ndimage import laplace
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import laplace

result_dir = "/tmp/slicer_task_results"
export_dir = "/home/ga/Documents/SlicerData/Exports"

print("Querying Slicer scene...")

# Get all volume nodes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
print(f"Found {len(volume_nodes)} volume node(s)")

volumes_info = []
smoothed_volume_found = False
smoothed_volume_name = None
original_volume_info = None

for node in volume_nodes:
    name = node.GetName()
    print(f"  Processing volume: {name}")
    
    # Get dimensions
    image_data = node.GetImageData()
    if image_data:
        dims = image_data.GetDimensions()
    else:
        dims = (0, 0, 0)
    
    # Get array for analysis
    try:
        array = slicer.util.arrayFromVolume(node)
        array_float = array.astype(np.float32)
        
        vol_info = {
            "name": name,
            "dimensions": list(dims),
            "min": float(array.min()),
            "max": float(array.max()),
            "mean": float(array.mean()),
            "std": float(array.std()),
        }
        
        # Compute edge sharpness metric (Laplacian)
        laplacian_mag = np.abs(laplace(array_float)).mean()
        vol_info["laplacian_mean"] = float(laplacian_mag)
        
    except Exception as e:
        print(f"    Error processing array: {e}")
        vol_info = {
            "name": name,
            "dimensions": list(dims),
            "error": str(e)
        }
    
    # Check if this is the original MRHead
    if name == "MRHead" or name.lower() == "mrhead":
        original_volume_info = vol_info.copy()
        vol_info["is_original"] = True
    
    # Check if this looks like a smoothed output
    name_lower = name.lower()
    if ("smooth" in name_lower or "gaussian" in name_lower or 
        "filtered" in name_lower or "blur" in name_lower):
        smoothed_volume_found = True
        smoothed_volume_name = name
        vol_info["is_smoothed_output"] = True
        
        # Save the smoothed volume as NRRD for verification
        try:
            output_path = os.path.join(export_dir, f"{name}.nrrd")
            slicer.util.saveNode(node, output_path)
            vol_info["exported_path"] = output_path
            vol_info["exported_size_bytes"] = os.path.getsize(output_path)
            print(f"    Exported to: {output_path}")
        except Exception as e:
            print(f"    Failed to export: {e}")
            vol_info["export_error"] = str(e)
    
    volumes_info.append(vol_info)

# If no obviously named smoothed volume, check for any new volume besides MRHead
if not smoothed_volume_found:
    print("No obviously named smoothed volume found, checking for new volumes...")
    for vol_info in volumes_info:
        name = vol_info.get("name", "")
        if name != "MRHead" and name.lower() != "mrhead":
            # This might be the output
            print(f"  Found potential output: {name}")
            vol_info["is_potential_output"] = True
            smoothed_volume_found = True
            smoothed_volume_name = name
            
            # Try to export this volume
            for node in volume_nodes:
                if node.GetName() == name:
                    try:
                        output_path = os.path.join(export_dir, f"{name}.nrrd")
                        slicer.util.saveNode(node, output_path)
                        vol_info["exported_path"] = output_path
                        vol_info["exported_size_bytes"] = os.path.getsize(output_path)
                        print(f"    Exported to: {output_path}")
                    except Exception as e:
                        print(f"    Failed to export: {e}")
                    break

# Compile result
result = {
    "slicer_running": True,
    "volume_count": len(volume_nodes),
    "volumes": volumes_info,
    "smoothed_volume_found": smoothed_volume_found,
    "smoothed_volume_name": smoothed_volume_name,
    "original_volume_info": original_volume_info,
}

# Save result
result_path = os.path.join(result_dir, "slicer_scene_info.json")
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nScene info exported to {result_path}")
print(f"Total volumes: {len(volume_nodes)}")
print(f"Smoothed volume found: {smoothed_volume_found}")
if smoothed_volume_name:
    print(f"Smoothed volume name: {smoothed_volume_name}")
PYEOF

    # Execute in Slicer (run in background with timeout)
    sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --no-splash --python-script /tmp/extract_smoothing_result.py > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait for extraction to complete
    echo "Waiting for Slicer extraction..."
    for i in {1..35}; do
        if [ -f "$RESULT_DIR/slicer_scene_info.json" ]; then
            echo "Scene info extracted successfully"
            break
        fi
        if ! kill -0 $EXTRACT_PID 2>/dev/null; then
            echo "Extraction process finished"
            break
        fi
        sleep 1
    done
    
    # Kill extraction if still running
    kill $EXTRACT_PID 2>/dev/null || true
    
    sleep 2
fi

# ============================================================
# Create final result JSON
# ============================================================
echo "Creating final result JSON..."

python3 << 'PYEOF'
import json
import os
import glob

result_dir = "/tmp/slicer_task_results"
screenshot_dir = "/home/ga/Documents/SlicerData/Screenshots"
export_dir = "/home/ga/Documents/SlicerData/Exports"

# Read task timing
task_start = 0
task_end = 0
try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = int(f.read().strip())
except:
    pass

try:
    import time
    task_end = int(time.time())
except:
    pass

result = {
    "task_start": task_start,
    "task_end": task_end,
    "task_duration_seconds": task_end - task_start if task_end and task_start else 0,
    "slicer_was_running": os.path.exists(os.path.join(result_dir, "slicer_scene_info.json")),
    "screenshot_exists": os.path.exists("/tmp/task_final.png"),
    "initial_stats_exist": os.path.exists(os.path.join(result_dir, "initial_stats.json")),
}

# Load scene info if available
if result["slicer_was_running"]:
    try:
        with open(os.path.join(result_dir, "slicer_scene_info.json")) as f:
            scene_info = json.load(f)
        result.update(scene_info)
    except Exception as e:
        result["scene_load_error"] = str(e)

# Load initial stats for comparison
if result["initial_stats_exist"]:
    try:
        with open(os.path.join(result_dir, "initial_stats.json")) as f:
            result["initial_stats"] = json.load(f)
    except Exception as e:
        result["initial_stats_error"] = str(e)

# Check for exported NRRD files
exported_files = glob.glob(os.path.join(export_dir, "*.nrrd"))
result["exported_nrrd_files"] = exported_files
result["exported_file_count"] = len(exported_files)

# Check if any exported files were created during task
new_exports = []
for f in exported_files:
    try:
        mtime = os.path.getmtime(f)
        if mtime > task_start:
            new_exports.append({
                "path": f,
                "size_bytes": os.path.getsize(f),
                "mtime": mtime
            })
    except:
        pass
result["new_exports_during_task"] = new_exports
result["new_export_count"] = len(new_exports)

# Save final result
result_path = os.path.join(result_dir, "result.json")
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

# Also save to /tmp for easy access
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

# Set permissions
chmod -R 755 "$RESULT_DIR" 2>/dev/null || true
chmod -R 755 "$EXPORT_DIR" 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 "$RESULT_DIR/result.json" 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
echo "Results saved to:"
echo "  - /tmp/task_result.json"
echo "  - $RESULT_DIR/result.json"
echo ""
cat /tmp/task_result.json 2>/dev/null || cat "$RESULT_DIR/result.json" 2>/dev/null || echo "Could not display result"