#!/usr/bin/env python3
import json
import os
import base64
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_contractor_activity(traj, env_info, task_info):
    """
    Verifies that the agent exported a CSV containing ONLY contractor records.
    
    Scoring Criteria:
    1. File 'contractor_activity.csv' exists and was created during task (20 pts)
    2. File format is effectively CSV/Text (10 pts)
    3. Contains 'Gary' and 'Spark' (Contractor 1) (20 pts)
    4. Contains 'FixIt' or 'Plumber' (Contractor 2) (20 pts)
    5. DOES NOT contain 'Alice' or 'Candidate' (Non-contractor) (30 pts)
       * This implies correct filtering *
       
    VLM Verification (Secondary check for process):
    - Confirms via trajectory if filtering UI was used.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Timestamp
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 20
        feedback.append("Output file created successfully.")
    elif output_exists:
        score += 10
        feedback.append("Output file exists but timestamp is old (reused file?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file contractor_activity.csv not found."}

    # 3. Analyze Content
    content_b64 = result.get('content_base64', "")
    try:
        content_bytes = base64.b64decode(content_b64)
        content_str = content_bytes.decode('utf-8', errors='ignore')
    except Exception:
        content_str = ""

    # Check Format (Basic CSV detection)
    if "," in content_str or "\t" in content_str:
        score += 10
        feedback.append("File format appears to be CSV/Tabular.")
    else:
        feedback.append("File content does not look like CSV.")

    # Check Inclusion (Contractors)
    # Gary Spark
    if "Gary" in content_str and "Spark" in content_str:
        score += 20
        feedback.append("Found Contractor 'Gary Spark'.")
    else:
        feedback.append("Missing Contractor 'Gary Spark'.")

    # FixIt Plumbers
    if "FixIt" in content_str or ("Joe" in content_str and "Plumber" in content_str):
        score += 20
        feedback.append("Found Contractor 'FixIt Plumbers'.")
    else:
        feedback.append("Missing Contractor 'FixIt Plumbers'.")

    # Check Exclusion (Non-Contractors) - CRITICAL for filtering
    # Alice Candidate (Interview)
    if "Alice" in content_str or "Candidate" in content_str:
        feedback.append("FAILED: Found Non-Contractor 'Alice Candidate' in export. Filtering was not applied correctly.")
    else:
        score += 30
        feedback.append("Correctly excluded Non-Contractor records.")

    # 4. VLM Verification (Trajectory Analysis)
    # Check if they actually interacted with the filter/search UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of a visitor management task. "
            "Did the user apply a filter or search to the visitor log? "
            "Look for: Search bars with text like 'Contractor', dropdown filters selected, "
            "or a list view showing only specific records."
        )
        # We don't strictly penalize score here as file content is the ground truth,
        # but we use it to confirm the method if content is borderline.
        # For this specific task, file content is definitive. 
        pass

    passed = (score >= 90) # Strict pass requires filtering
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }