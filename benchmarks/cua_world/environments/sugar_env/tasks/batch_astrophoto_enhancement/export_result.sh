#!/bin/bash
echo "=== Exporting batch_astrophoto_enhancement task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Use Python to safely analyze ImageMagick metadata and script contents, outputting reliable JSON
python3 << 'PYEOF' > /tmp/batch_astrophoto_result.json
import json
import os
import glob
import subprocess

result = {
    "task_start_time": 0,
    "script_exists": False,
    "has_magick": False,
    "has_loop": False,
    "out_dir_exists": False,
    "processed_files": [],
    "script_mtime": 0,
    "error": None
}

try:
    if os.path.exists("/tmp/task_start_time.txt"):
        with open("/tmp/task_start_time.txt", "r") as f:
            result["task_start_time"] = int(f.read().strip())
except Exception:
    pass

script_path = "/home/ga/Documents/enhance_astrophotos.sh"
try:
    if os.path.exists(script_path):
        result["script_exists"] = True
        result["script_mtime"] = os.path.getmtime(script_path)
        with open(script_path, "r") as f:
            content = f.read()
            # Check for standard ImageMagick tools
            result["has_magick"] = "convert " in content or "mogrify " in content
            # Check for batch processing constructs
            result["has_loop"] = "for " in content or "while " in content or "find " in content or "xargs" in content
except Exception as e:
    result["error"] = str(e)

out_dir = "/home/ga/Documents/enhanced_astro"
try:
    if os.path.exists(out_dir) and os.path.isdir(out_dir):
        result["out_dir_exists"] = True
        
        # Search for jpg files (case insensitive)
        jpg_files = glob.glob(os.path.join(out_dir, "*.[jJ][pP][gG]"))
        
        for f in jpg_files:
            basename = os.path.basename(f)
            raw_file = os.path.join("/home/ga/Documents/raw_astro", basename)
            
            file_data = {
                "name": basename,
                "w": 0, "h": 0,
                "mean": 0.0,
                "raw_mean": 0.0,
                "mtime": os.path.getmtime(f)
            }
            
            try:
                # Use ImageMagick 'identify' to get width, height, and overall mean pixel brightness
                out_info = subprocess.check_output(["identify", "-format", "%w %h %[mean]", f]).decode("utf-8").strip().split()
                if len(out_info) >= 3:
                    file_data["w"] = int(out_info[0])
                    file_data["h"] = int(out_info[1])
                    file_data["mean"] = float(out_info[2])
                
                # Compare to the original file if it still exists
                if os.path.exists(raw_file):
                    raw_info = subprocess.check_output(["identify", "-format", "%[mean]", raw_file]).decode("utf-8").strip()
                    file_data["raw_mean"] = float(raw_info)
            except Exception:
                pass
                
            result["processed_files"].append(file_data)
except Exception as e:
    if not result["error"]:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/batch_astrophoto_result.json
echo "Result JSON saved to /tmp/batch_astrophoto_result.json"
cat /tmp/batch_astrophoto_result.json
echo -e "\n=== Export complete ==="