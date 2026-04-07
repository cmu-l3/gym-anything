#!/bin/bash
echo "=== Exporting BRCA1 CRISPR Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/crispr/results"

# Execute Python script to validate biological properties of exported files
python3 << PYEOF
import os
import json
import re

task_start = int("${TASK_START}")
results_dir = "${RESULTS_DIR}"

gb_file = os.path.join(results_dir, "BRCA1_crispr.gb")
csv_file = os.path.join(results_dir, "crispr_targets.csv")
summary_file = os.path.join(results_dir, "design_summary.txt")

result = {
    "gb_exists": False,
    "gb_created_during_task": False,
    "csv_exists": False,
    "csv_created_during_task": False,
    "summary_exists": False,
    "summary_created_during_task": False,
    "feature_count": 0,
    "all_length_23": False,
    "all_valid_pam": False,
    "summary_count": -1,
    "error": ""
}

def check_file(path):
    if os.path.exists(path):
        mtime = os.path.getmtime(path)
        return True, mtime > task_start
    return False, False

result["gb_exists"], result["gb_created_during_task"] = check_file(gb_file)
result["csv_exists"], result["csv_created_during_task"] = check_file(csv_file)
result["summary_exists"], result["summary_created_during_task"] = check_file(summary_file)

if result["summary_exists"]:
    try:
        with open(summary_file, "r") as f:
            content = f.read()
            nums = re.findall(r"\d+", content)
            if nums:
                result["summary_count"] = int(nums[0])
    except Exception:
        pass

if result["gb_exists"]:
    try:
        with open(gb_file, "r") as f:
            gb_content = f.read()

        # Extract sequence from ORIGIN block
        origin_match = re.search(r"ORIGIN\s+(.*?)(?://|$)", gb_content, re.DOTALL)
        sequence = ""
        if origin_match:
            sequence = re.sub(r"[\s\d]", "", origin_match.group(1)).upper()

        # Extract FEATURES block
        features_block_match = re.search(r"FEATURES\s+Location/Qualifiers\s+(.*?)(?:ORIGIN|$)", gb_content, re.DOTALL)
        
        if features_block_match and sequence:
            features_text = features_block_match.group(1)
            # Find feature coordinates
            feature_lines = re.findall(r"^\s+([A-Za-z0-9_]+)\s+(complement\(\d+\.\.\d+\)|\d+\.\.\d+)", features_text, re.MULTILINE)
            
            count = 0
            valid_length = True
            valid_pam = True
            
            for ftype, coords in feature_lines:
                if ftype.lower() == "source":
                    continue
                
                count += 1
                is_complement = "complement" in coords
                nums = re.findall(r"\d+", coords)
                
                if len(nums) >= 2:
                    start = int(nums[0])
                    end = int(nums[1])
                    length = end - start + 1
                    
                    if length != 23:
                        valid_length = False
                    
                    # Validate PAM directly from origin sequence (1-indexed)
                    if is_complement:
                        # Target on reverse strand. PAM at 3' of reverse = 5' of forward.
                        # NGG on reverse -> CCN on forward. 
                        pam_seq = sequence[start-1 : start+1] # First 2 bases on forward
                        if pam_seq != "CC":
                            valid_pam = False
                    else:
                        # Target on forward strand. PAM at 3' of forward.
                        # Ends with GG.
                        pam_seq = sequence[end-2 : end] # Last 2 bases on forward
                        if pam_seq != "GG":
                            valid_pam = False

            result["feature_count"] = count
            if count > 0:
                result["all_length_23"] = valid_length
                result["all_valid_pam"] = valid_pam

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="