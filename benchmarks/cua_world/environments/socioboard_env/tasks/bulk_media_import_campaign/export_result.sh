#!/bin/bash
echo "=== Exporting bulk_media_import_campaign task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual and trajectory verification
take_screenshot /tmp/task_end.png

# Run Python script to securely gather results without bash escaping issues
python3 << 'PYEOF'
import os
import json
import time
import subprocess
from pymongo import MongoClient

result = {
    "task_start": 0,
    "initial_media_count": 0,
    "final_media_count": 0,
    "dir_exists": False,
    "processed_files": [],
    "error": None
}

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        result["task_start"] = float(f.read().strip())
except Exception:
    pass

try:
    with open('/tmp/initial_media_count', 'r') as f:
        result["initial_media_count"] = int(f.read().strip())
except Exception:
    pass

# Check MongoDB for final media count
try:
    client = MongoClient("mongodb://localhost:27017/", serverSelectionTimeoutMS=2000)
    db = client.socioboard
    count = 0
    for coll_name in ["user_medias", "user_media", "media_informations"]:
        if coll_name in db.list_collection_names():
            count += db[coll_name].count_documents({})
    result["final_media_count"] = count
except Exception as e:
    result["error"] = f"MongoDB query failed: {str(e)}"

# Check processed files directory
processed_dir = "/home/ga/Documents/Processed_Campaign"
result["dir_exists"] = os.path.exists(processed_dir)

if result["dir_exists"]:
    for fname in os.listdir(processed_dir):
        fpath = os.path.join(processed_dir, fname)
        if os.path.isfile(fpath) and fname.lower().endswith(('.jpg', '.jpeg', '.png')):
            mtime = os.path.getmtime(fpath)
            
            # Use ImageMagick 'identify' to get width safely
            width = 0
            try:
                out = subprocess.check_output(['identify', '-format', '%w', fpath], stderr=subprocess.DEVNULL)
                width = int(out.decode('utf-8').strip())
            except Exception:
                pass
                
            result["processed_files"].append({
                "name": fname,
                "width": width,
                "mtime": mtime
            })

# Save result safely
temp_json = f"/tmp/result_{int(time.time())}.json"
with open(temp_json, 'w') as f:
    json.dump(result, f)

# Move to final location
os.system(f"cp {temp_json} /tmp/task_result.json && chmod 666 /tmp/task_result.json")
os.remove(temp_json)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="