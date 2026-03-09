#!/bin/bash
set -e
echo "=== Exporting texture_bake_game_export results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a Python script to analyze the images and the blend file
# We use system python for PIL/numpy image analysis
# We use Blender python for checking internal scene state
# This script does everything by invoking blender as a subprocess for the blend check part

cat > /tmp/analyze_results.py << 'PYEOF'
import json
import os
import sys
import subprocess
import tempfile
import time

result = {
    "task_start_time": 0,
    "timestamp_check_passed": False,
    "ao_image": {
        "exists": False,
        "width": 0,
        "height": 0,
        "size_bytes": 0,
        "pixel_mean": 0,
        "pixel_std": 0,
        "is_grayscale": False
    },
    "diffuse_image": {
        "exists": False,
        "width": 0,
        "height": 0,
        "size_bytes": 0,
        "red_mean": 0,
        "green_mean": 0,
        "blue_mean": 0,
        "pixel_std": 0,
        "red_dominant": False
    },
    "blend_file": {
        "exists": False,
        "valid_magic": False,
        "has_image_nodes": False,
        "render_engine": None
    },
    "errors": []
}

# 1. Get task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    result["errors"].append("Could not read task_start_time")

task_start = result["task_start_time"]

# 2. Analyze AO Image
ao_path = "/home/ga/BlenderProjects/baked_ao.png"
if os.path.exists(ao_path):
    stat = os.stat(ao_path)
    result["ao_image"]["size_bytes"] = stat.st_size
    # Check timestamp
    if stat.st_mtime > task_start:
        result["ao_image"]["exists"] = True
    
    if result["ao_image"]["exists"]:
        try:
            from PIL import Image
            import numpy as np
            img = Image.open(ao_path)
            result["ao_image"]["width"] = img.width
            result["ao_image"]["height"] = img.height
            
            arr = np.array(img.convert("RGB"), dtype=np.float64)
            result["ao_image"]["pixel_mean"] = float(np.mean(arr))
            result["ao_image"]["pixel_std"] = float(np.std(arr))
            
            # Grayscale check
            r = arr[:,:,0]
            g = arr[:,:,1]
            b = arr[:,:,2]
            # Max difference between channels should be low for AO
            channel_diff = np.max([np.abs(r-g), np.abs(g-b), np.abs(r-b)])
            result["ao_image"]["is_grayscale"] = float(channel_diff) < 5.0
            
        except Exception as e:
            result["errors"].append(f"AO analysis failed: {e}")

# 3. Analyze Diffuse Image
diff_path = "/home/ga/BlenderProjects/baked_diffuse.png"
if os.path.exists(diff_path):
    stat = os.stat(diff_path)
    result["diffuse_image"]["size_bytes"] = stat.st_size
    if stat.st_mtime > task_start:
        result["diffuse_image"]["exists"] = True
        
    if result["diffuse_image"]["exists"]:
        try:
            from PIL import Image
            import numpy as np
            img = Image.open(diff_path)
            result["diffuse_image"]["width"] = img.width
            result["diffuse_image"]["height"] = img.height
            
            arr = np.array(img.convert("RGB"), dtype=np.float64)
            r_mean = float(np.mean(arr[:,:,0]))
            g_mean = float(np.mean(arr[:,:,1]))
            b_mean = float(np.mean(arr[:,:,2]))
            result["diffuse_image"]["red_mean"] = r_mean
            result["diffuse_image"]["green_mean"] = g_mean
            result["diffuse_image"]["blue_mean"] = b_mean
            result["diffuse_image"]["pixel_std"] = float(np.std(arr))
            
            # Check red dominance (material is 0.8, 0.2, 0.2)
            result["diffuse_image"]["red_dominant"] = (r_mean > g_mean + 20) and (r_mean > b_mean + 20)
            
        except Exception as e:
            result["errors"].append(f"Diffuse analysis failed: {e}")

# 4. Analyze Blend File (Magic Bytes & Content)
blend_path = "/home/ga/BlenderProjects/bake_project.blend"
if os.path.exists(blend_path):
    stat = os.stat(blend_path)
    if stat.st_mtime > task_start:
        result["blend_file"]["exists"] = True
        
    if result["blend_file"]["exists"]:
        # Check magic
        with open(blend_path, 'rb') as f:
            if f.read(7) == b'BLENDER':
                result["blend_file"]["valid_magic"] = True

        # Deep inspection using Blender
        if result["blend_file"]["valid_magic"]:
            blender_script = """
import bpy
import json
info = {
    "engine": bpy.context.scene.render.engine,
    "has_image_nodes": False
}
cube = bpy.data.objects.get("BaseCube")
if cube and cube.data.materials:
    mat = cube.data.materials[0]
    if mat and mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                info["has_image_nodes"] = True
                break
print("BLEND_ANALYSIS:" + json.dumps(info))
"""
            try:
                with tempfile.NamedTemporaryFile(mode='w', suffix='.py') as tf:
                    tf.write(blender_script)
                    tf.flush()
                    cmd = ["/opt/blender/blender", "--background", blend_path, "--python", tf.name]
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                    
                    for line in proc.stdout.split('\n'):
                        if line.startswith("BLEND_ANALYSIS:"):
                            data = json.loads(line[15:])
                            result["blend_file"]["render_engine"] = data.get("engine")
                            result["blend_file"]["has_image_nodes"] = data.get("has_image_nodes")
            except Exception as e:
                result["errors"].append(f"Blender inspection failed: {e}")

# Timestamp check summary
if (result["ao_image"]["exists"] or 
    result["diffuse_image"]["exists"] or 
    result["blend_file"]["exists"]):
    result["timestamp_check_passed"] = True

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Run the analysis
python3 /tmp/analyze_results.py

echo "=== Export complete ==="