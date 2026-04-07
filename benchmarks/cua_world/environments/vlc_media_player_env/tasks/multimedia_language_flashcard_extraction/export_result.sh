#!/bin/bash
echo "=== Exporting Flashcard Extraction Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We run a Python script inside the container to safely analyze media 
# files using ffprobe, outputting a rich JSON for the host verifier.
# This strictly avoids attempting to copy massive MP4s out of the container.
cat > /tmp/analyze_results.py << 'PYEOF'
import json
import os
import subprocess

def probe_file(filepath):
    try:
        cmd = [
            'ffprobe', '-v', 'error', 
            '-show_format', '-show_streams', 
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if res.returncode == 0:
            return json.loads(res.stdout)
    except Exception as e:
        pass
    return None

def main():
    task_start = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0
    target_dir = "/home/ga/Documents/AnkiDeck"
    
    result = {
        "ankideck_exists": os.path.isdir(target_dir),
        "files": {},
        "manifest": None,
        "manifest_valid": False,
        "screenshot_exists": os.path.exists("/tmp/task_final.png")
    }

    if result["ankideck_exists"]:
        for f in os.listdir(target_dir):
            path = os.path.join(target_dir, f)
            if not os.path.isfile(path):
                continue
            
            size = os.path.getsize(path)
            mtime = os.path.getmtime(path)
            
            if f == "deck_manifest.json":
                try:
                    with open(path, 'r', encoding='utf-8') as mf:
                        result["manifest"] = json.load(mf)
                        result["manifest_valid"] = True
                except:
                    result["manifest_valid"] = False
                continue
            
            file_info = {
                "size_bytes": size,
                "created_during_task": mtime >= (task_start - 5)
            }
            
            # Use ffprobe on media files
            if f.endswith(".mp3") or f.endswith(".mp4"):
                probe_data = probe_file(path)
                if probe_data:
                    file_info["probe"] = probe_data
                    
            result["files"][f] = file_info

    with open("/tmp/task_result.json", "w", encoding='utf-8') as out:
        json.dump(result, out, indent=2)

if __name__ == "__main__":
    main()
PYEOF

# Run analysis
python3 /tmp/analyze_results.py

# Ensure safe permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Media analysis complete. Result saved to /tmp/task_result.json."
echo "=== Export complete ==="