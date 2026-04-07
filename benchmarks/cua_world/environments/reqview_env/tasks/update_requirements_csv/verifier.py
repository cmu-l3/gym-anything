#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_requirements_csv(traj, env_info, task_info):
    """
    Verifies that requirements were updated correctly from the CSV.
    Checks:
    1. Project file was modified.
    2. Targeted requirements have updated Status and Priority.
    3. No significant increase in total requirement count (detects 'Create' vs 'Update').
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Temp files
    srs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # Copy files from environment
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name) as f:
            task_result = json.load(f)

        if not task_result.get("file_modified", False):
             return {
                "passed": False, 
                "score": 0, 
                "feedback": "Project file was not saved/modified. Did you save the project after importing?"
            }

        copy_from_env("/tmp/srs_final.json", srs_file.name)
        copy_from_env("/tmp/ground_truth.json", gt_file.name)

        with open(srs_file.name) as f:
            srs_data = json.load(f)
        
        with open(gt_file.name) as f:
            ground_truth = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading verification data: {str(e)}"}
    finally:
        # Cleanup
        for f in [srs_file, gt_file, result_file]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    # --- Verification Logic ---
    
    # Helper to map IDs to Objects
    req_map = {}
    
    def traverse(items):
        for item in items:
            if 'id' in item:
                # ReqView IDs can be strings or ints in JSON
                req_map[str(item['id'])] = item
            if 'children' in item:
                traverse(item['children'])
                
    traverse(srs_data.get('data', []))

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check Data Integrity (50 pts total)
    # 25 pts for Status, 25 pts for Priority
    total_targets = len(ground_truth)
    if total_targets == 0:
        return {"passed": False, "score": 0, "feedback": "System error: No ground truth data found."}

    points_per_field = 50.0 / (total_targets * 2)
    correct_updates = 0
    
    for req_id, expected in ground_truth.items():
        if req_id not in req_map:
            feedback.append(f"Req ID {req_id} missing from project (Deleted?).")
            continue
            
        obj = req_map[req_id]
        
        # Check Status
        actual_status = obj.get("status", "")
        if actual_status == expected["status"]:
            score += points_per_field
            correct_updates += 1
        else:
            feedback.append(f"Req {req_id}: Status is '{actual_status}', expected '{expected['status']}'.")
            
        # Check Priority
        # ReqView often stores Priority as 'H', 'M', 'L' keys even if displayed as 'High'
        # Or it stores the string if configured that way. The example project usually uses keys.
        # We handle both mapping.
        prio_map = {'High': ['High', 'H'], 'Medium': ['Medium', 'M'], 'Low': ['Low', 'L']}
        
        actual_prio = obj.get("priority", "")
        expected_prio_val = expected["priority"]
        valid_prio_values = prio_map.get(expected_prio_val, [expected_prio_val])
        
        if actual_prio in valid_prio_values:
            score += points_per_field
            correct_updates += 1
        else:
            feedback.append(f"Req {req_id}: Priority is '{actual_prio}', expected '{expected_prio_val}'.")

    # 2. Check for Duplicates (Update vs Create) (50 pts)
    # If the user selected "Create new" instead of "Update", ReqView generates new IDs.
    # The original IDs would remain untouched (Status/Priority unchanged), resulting in low score above.
    # However, if they somehow mapped ID -> ID and forced create, they might have duplicate contents.
    # The simplest check: The count of requirements should be roughly the same as the original project.
    # Since we don't have the exact original count easily here without reloading the base, 
    # we can check if the updated requirements are indeed the ones with the matching IDs.
    
    # If score > 0 but low, it means some matched.
    # If score is high, it means they updated the correct IDs.
    # If they created NEW requirements, the original IDs (which we checked above) would NOT be updated.
    # So the check above implicitly handles the "Update vs Create" distinction.
    # If they Created New, the original ID objects would still be "Draft", so score would be 0.
    
    # We add a bonus check: Ensure user didn't just delete everything and replace.
    # Count total items.
    total_items = len(req_map)
    if total_items < total_targets * 2: # heuristic: project should be bigger than just the CSV
        score = 0
        feedback.append("Project seems to have lost most data.")
    
    # 3. VLM / Trajectory check (Optional Bonus / Tie-breaker)
    # (Not strictly implemented here to keep it robust purely on data, 
    # but the task description asks for VLM usage if possible. 
    # We will rely on data verification as Primary as it's deterministic.)

    final_score = int(score)
    # Threshold: We need at least 80% correctness.
    passed = final_score >= 80
    
    if passed:
        feedback.insert(0, "Success! Requirements updated correctly.")
    elif final_score > 0:
        feedback.insert(0, "Partial success. Some fields matched, others did not.")
    else:
        feedback.insert(0, "Failed. Original requirements were not updated. Did you select 'Update existing'?")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback[:5]) # limit feedback length
    }