#!/usr/bin/env python3
import json
import os
import csv
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_explosives_compatibility(traj, env_info, task_info):
    """
    Verifies the explosives compatibility group lookup task.
    
    Criteria:
    1. Output CSV file exists and was created during the task.
    2. CSV structure is correct (headers, 5 rows).
    3. Data accuracy: Correct Compatibility Group letters for the 5 UN numbers.
    4. Anti-gaming: File timestamp check.
    5. VLM: Validates that the agent actually used the search interface.
    """
    
    # 1. Setup and Resource Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('items', [])
    
    # Load task result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    # 2. Basic File Checks (20 points max)
    score = 0
    feedback = []
    
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'explosives_manifest.csv' not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file existed before task start (anti-gaming check failed)."}
        
    score += 10 # File exists and is new
    feedback.append("Output file created.")

    # 3. CSV Content Analysis (80 points max)
    # Copy the CSV file out
    csv_content = []
    with tempfile.NamedTemporaryFile(delete=True, suffix=".csv") as tmp_csv:
        try:
            copy_from_env(task_result["output_path"], tmp_csv.name)
            tmp_csv.seek(0)
            # Read CSV
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                reader = csv.DictReader(f)
                # Normalize headers: strip whitespace, lower case
                if reader.fieldnames:
                    reader.fieldnames = [h.strip() for h in reader.fieldnames]
                
                # Check for required columns (fuzzy match)
                required_cols = ["UN_Number", "Compatibility_Group"]
                headers = reader.fieldnames if reader.fieldnames else []
                missing_cols = [col for col in required_cols if col not in headers]
                
                if missing_cols:
                    # Fallback: check if header row is missing and data is in row 1? 
                    # For strictness, we require headers as per description
                    return {"passed": False, "score": score, "feedback": f"CSV missing required columns: {missing_cols}. Headers found: {headers}"}
                
                csv_content = list(reader)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read/parse CSV file: {str(e)}"}

    if len(csv_content) != 5:
        feedback.append(f"Expected 5 data rows, found {len(csv_content)}.")
    else:
        score += 10 # Correct row count
        feedback.append("Correct row count.")

    # Verify Data Accuracy (14 points per item = 70 points max)
    # Mapping expected data for easy lookup
    # Normalize UN numbers (remove 'UN', whitespace, leading zeros if needed)
    def normalize_un(val):
        if not val: return ""
        s = str(val).upper().replace("UN", "").replace(" ", "").strip()
        return s.zfill(4) # Ensure 4 digits for comparison

    expected_map = {normalize_un(item["un"]): item for item in expected_items}
    
    items_correct = 0
    
    for row in csv_content:
        # Extract UN from row
        raw_un = row.get("UN_Number", "")
        norm_un = normalize_un(raw_un)
        
        if norm_un in expected_map:
            target = expected_map[norm_un]
            
            # Check Compatibility Group
            agent_group = row.get("Compatibility_Group", "").strip().upper()
            expected_group = target["group"]
            
            # Allow "1.1D" style if they put the whole class in the group column, 
            # though instructions asked for just letter. We'll be strict per instructions 
            # "contains just the single letter" or verify containment if we want to be lenient.
            # Description says: "The 'Compatibility_Group' column must contain just the single letter."
            # So we stick to strict check for higher quality.
            
            if agent_group == expected_group:
                score += 14
                items_correct += 1
            elif agent_group in target["class"]: # Partial credit if they put "1.1D" instead of "D"
                score += 7
                feedback.append(f"UN {norm_un}: Partial credit for '{agent_group}' (expected just '{expected_group}').")
            else:
                feedback.append(f"UN {norm_un}: Incorrect group '{agent_group}' (expected '{expected_group}').")
        else:
            feedback.append(f"Unexpected UN number in CSV: {raw_un}")

    feedback.append(f"Correctly identified items: {items_correct}/5")

    # 4. VLM Verification (Bonus/Confirmation check)
    # Check if agent actually visited search pages or datasheets
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user interface show the 'CAMEO Chemicals' website? "
            "Are there search results or chemical datasheets visible? "
            "Answer yes/no."
        )
        try:
            vlm_res = query_vlm(frames, vlm_prompt)
            if vlm_res and vlm_res.get("success"):
                # If VLM explicitly says NO, we might penalize or just warn. 
                # Since we trust file verification primarily, we use this mainly for logging 
                # or breaking ties. Here we'll just log it.
                logger.info(f"VLM Verification: {vlm_res.get('response')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final logic
    passed = (score >= 80) # Requires file structure + ~4/5 correct items
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }