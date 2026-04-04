#!/usr/bin/env python3
"""
Verifier for Venetoclax Polypharmacy Audit Task.
Checks correctness of the generated CSV report and verifies visual workflow using VLM.
"""

import json
import tempfile
import os
import csv
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though usually injected by framework. 
# We assume gym_anything.vlm interface is available or we use the trajectory directly.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_venetoclax_audit(traj, env_info, task_info):
    """
    Verifies the audit_polypharmacy_for_venetoclax_start task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_interactions = metadata.get('interactions', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve and Check Task Result JSON
    # =========================================================
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not task_result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}

    if not task_result.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task session (anti-gaming check failed)."}

    # =========================================================
    # 2. Retrieve and Parse CSV Content
    # =========================================================
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    parsed_data = {}
    
    try:
        copy_from_env(task_result['csv_path'], temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
            # Flexible parsing: try standard CSV, if fail, try simple line parsing
            try:
                reader = csv.DictReader(f)
                # Normalize headers if possible
                if reader.fieldnames:
                    headers = [h.strip().lower() for h in reader.fieldnames]
                    if 'medication' in headers and 'color' in headers:
                        score += 20 # Structure valid
                        feedback_parts.append("Valid CSV structure (20/20)")
                        
                        # Reset file pointer to read rows
                        f.seek(0)
                        reader = csv.DictReader(f)
                        for row in reader:
                            # Normalize keys
                            clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
                            med = clean_row.get('medication', '').lower()
                            color = clean_row.get('color', '').lower()
                            if med:
                                parsed_data[med] = color
                    else:
                        feedback_parts.append("CSV headers missing 'Medication' or 'Color'")
                else:
                    feedback_parts.append("Empty CSV file")
            except Exception as csv_e:
                feedback_parts.append(f"CSV parsing error: {csv_e}")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV content: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # =========================================================
    # 3. Verify Data Accuracy
    # =========================================================
    
    # Helper to fuzzy match medication names
    def get_reported_color(target_med):
        target_med = target_med.lower()
        for med, color in parsed_data.items():
            if target_med in med or med in target_med:
                return color
        return None

    # Check Clarithromycin (Red) - Critical
    clarithro_color = get_reported_color('clarithromycin')
    if clarithro_color and 'red' in clarithro_color:
        score += 25
        feedback_parts.append("Clarithromycin correct (Red) (25/25)")
    else:
        feedback_parts.append(f"Clarithromycin incorrect/missing (Expected: Red, Got: {clarithro_color})")

    # Check Verapamil (Orange)
    verapamil_color = get_reported_color('verapamil')
    if verapamil_color and ('orange' in verapamil_color or 'amber' in verapamil_color):
        score += 15
        feedback_parts.append("Verapamil correct (Orange) (15/15)")
    else:
        feedback_parts.append(f"Verapamil incorrect/missing (Expected: Orange, Got: {verapamil_color})")

    # Check Metformin (Green)
    metformin_color = get_reported_color('metformin')
    if metformin_color and 'green' in metformin_color:
        score += 10
        feedback_parts.append("Metformin correct (Green) (10/10)")
    else:
        feedback_parts.append(f"Metformin incorrect/missing (Expected: Green, Got: {metformin_color})")

    # Check Lisinopril (Green)
    lisinopril_color = get_reported_color('lisinopril')
    if lisinopril_color and 'green' in lisinopril_color:
        score += 10
        feedback_parts.append("Lisinopril correct (Green) (10/10)")
    else:
        feedback_parts.append(f"Lisinopril incorrect/missing (Expected: Green, Got: {lisinopril_color})")

    # =========================================================
    # 4. VLM Trajectory Verification
    # =========================================================
    
    # We want to verify the agent actually navigated to different categories
    # and selected the correct cancer drug.
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The task was to check 'Venetoclax' against 4 drugs: Clarithromycin (Antibacterial), Verapamil (Cardiovascular), Metformin (Antidiabetic), Lisinopril (Cardiovascular/ACE).
    
    Look at the sequence of screenshots. Answer the following in JSON format:
    1. Did the agent select "Venetoclax" as the Cancer Drug at some point? (look for 'Venetoclax' at the top of the screen)
    2. Did the agent navigate to at least 2 different Co-medication categories (e.g. Antibacterials, Cardiovascular, Endocrine/Diabetic)?
    3. Did the agent seemingly perform the task correctly?
    
    Output JSON keys: "venetoclax_selected" (bool), "categories_visited_count" (int), "workflow_valid" (bool).
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('venetoclax_selected', False):
            vlm_score += 10
            feedback_parts.append("VLM: Venetoclax selection confirmed")
        
        cat_count = parsed.get('categories_visited_count', 0)
        if cat_count >= 2:
            vlm_score += 10
            feedback_parts.append(f"VLM: Navigation confirmed ({cat_count} categories)")
        elif cat_count == 1:
            vlm_score += 5
            feedback_parts.append("VLM: Limited navigation detected")
            
        score += vlm_score
        feedback_parts.append(f"Process verification ({vlm_score}/20)")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if text verification was perfect, give full credit for VLM to avoid punishing VLM errors
        if score >= 80: 
            score += 20
            feedback_parts.append("VLM check skipped (Text correct)")
    
    # =========================================================
    # Final Result
    # =========================================================
    passed = score >= 75 and (clarithro_color and 'red' in clarithro_color)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }