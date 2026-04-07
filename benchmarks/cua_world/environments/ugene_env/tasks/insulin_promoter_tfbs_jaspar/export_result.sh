#!/bin/bash
set -e
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/tfbs_results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Extract properties via Python to build JSON
python3 << PYEOF
import json
import os
import re

task_start = int("$TASK_START")
results_dir = "$RESULTS_DIR"

def get_file_info(filepath):
    exists = os.path.exists(filepath) and os.path.isfile(filepath)
    if not exists:
        return {"exists": False, "size": 0, "created_during_task": False, "content": ""}
    
    size = os.path.getsize(filepath)
    mtime = os.path.getmtime(filepath)
    created_during_task = mtime >= task_start
    
    # Read a snippet of content for verification
    content = ""
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except:
        pass
        
    return {
        "exists": exists,
        "size": size,
        "created_during_task": created_during_task,
        "content": content
    }

gb_info = get_file_info(os.path.join(results_dir, "insulin_tfbs_annotated.gb"))
gff_info = get_file_info(os.path.join(results_dir, "predicted_sites.gff"))
txt_info = get_file_info(os.path.join(results_dir, "tfbs_summary.txt"))

# Parse GB
gb_valid = "LOCUS" in gb_info["content"] and "ORIGIN" in gb_info["content"]
gb_has_tbp = bool(re.search(r'TBP', gb_info["content"], re.IGNORECASE))
gb_has_sp1 = bool(re.search(r'SP1', gb_info["content"], re.IGNORECASE))

# Parse GFF
gff_valid = len(gb_info["content"]) > 0 and len(gb_info["content"].splitlines()) > 0
gff_has_tbp = bool(re.search(r'TBP', gff_info["content"], re.IGNORECASE))
gff_has_sp1 = bool(re.search(r'SP1', gff_info["content"], re.IGNORECASE))

# Parse TXT
txt_has_85 = "85" in txt_info["content"]
txt_has_tbp = bool(re.search(r'TBP', txt_info["content"], re.IGNORECASE))
txt_has_sp1 = bool(re.search(r'SP1', txt_info["content"], re.IGNORECASE))
txt_has_reg = bool(re.search(r'regul|bind|transcript', txt_info["content"], re.IGNORECASE))

result = {
    "app_running": "$APP_RUNNING" == "true",
    "gb_file": {
        "exists": gb_info["exists"],
        "created_during_task": gb_info["created_during_task"],
        "size": gb_info["size"],
        "valid_format": gb_valid,
        "has_tbp": gb_has_tbp,
        "has_sp1": gb_has_sp1
    },
    "gff_file": {
        "exists": gff_info["exists"],
        "created_during_task": gff_info["created_during_task"],
        "size": gff_info["size"],
        "valid_format": gff_valid,
        "has_tbp": gff_has_tbp,
        "has_sp1": gff_has_sp1
    },
    "txt_file": {
        "exists": txt_info["exists"],
        "created_during_task": txt_info["created_during_task"],
        "size": txt_info["size"],
        "has_85": txt_has_85,
        "has_tbp": txt_has_tbp,
        "has_sp1": txt_has_sp1,
        "has_regulation_keyword": txt_has_reg
    }
}

# Save securely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="