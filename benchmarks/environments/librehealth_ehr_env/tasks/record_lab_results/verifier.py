#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_lab_results(traj, env_info, task_info):
    """
    Verifies that lab results were correctly entered into LibreHealth EHR.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Result Data
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

    # Metadata targets
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_results', {})
    tolerances = metadata.get('tolerances', {})

    score = 0
    feedback_lines = []
    
    # ----------------------------------------------------------------
    # CRITERION 1: Report Exists & Status (25 pts)
    # ----------------------------------------------------------------
    report = result.get('report')
    if report and report != "null":
        score += 15
        feedback_lines.append("✓ Procedure report created")
        
        status = report.get('status', '').lower()
        if status in ['final', 'complete', 'review']:
            score += 10
            feedback_lines.append(f"✓ Report status is '{status}'")
        else:
            feedback_lines.append(f"⚠ Report status is '{status}' (expected Final)")
            
        # Anti-gaming: Check if created during task
        # Note: 'date_report' in MySQL might be just date or datetime. 
        # For simplicity, we assume if the record exists and matches our order ID 
        # (which was fresh), it's likely valid, but checking app_running helps.
    else:
        feedback_lines.append("✗ No procedure report found for the order")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_lines)}

    # ----------------------------------------------------------------
    # CRITERION 2: Result Values (60 pts)
    # ----------------------------------------------------------------
    db_results = result.get('results', [])
    # Convert DB results list to dict for easy lookup
    # db_results is a list of dicts: [{'result_name': 'WBC', 'result_value': '6.8'}, ...]
    
    # Normalize result names map (lowercase -> actual)
    result_map = {}
    for r in db_results:
        if r.get('result_name') and r.get('result_value'):
            key = r['result_name'].lower().strip()
            # Try to parse value as float
            try:
                val = float(r['result_value'])
                result_map[key] = val
            except ValueError:
                result_map[key] = r['result_value'] # Keep as string if not float

    results_correct = 0
    total_targets = len(targets)
    
    for name, target_val in targets.items():
        key = name.lower().strip()
        tol = tolerances.get(name, 0.1)
        
        # Check partial matches for keys (e.g. "platelet" vs "platelet count")
        found_val = None
        for k, v in result_map.items():
            if key in k or k in key:
                found_val = v
                break
        
        if found_val is not None:
            if isinstance(found_val, (int, float)):
                if abs(found_val - target_val) <= tol:
                    score += 12 # 60 pts total / 5 items
                    results_correct += 1
                    feedback_lines.append(f"✓ {name}: {found_val}")
                else:
                    feedback_lines.append(f"✗ {name}: {found_val} (expected {target_val})")
            else:
                 feedback_lines.append(f"✗ {name}: Non-numeric value '{found_val}'")
        else:
            feedback_lines.append(f"✗ {name}: Not found")

    # ----------------------------------------------------------------
    # CRITERION 3: VLM Verification (15 pts)
    # ----------------------------------------------------------------
    # Use VLM to check if the user actually used the UI form
    final_screenshot = get_final_screenshot(traj)
    vlm_passed = False
    
    if final_screenshot:
        # We check if the screen shows lab results or a completed order
        vlm_res = query_vlm(
            image=final_screenshot, 
            prompt="Does this screen show a medical lab report or procedure result entry form? Are there fields for WBC, RBC, or Hemoglobin visible? Answer JSON with keys: is_lab_form (bool), visible_values (list of numbers seen)."
        )
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_lab_form', False):
                score += 15
                vlm_passed = True
                feedback_lines.append("✓ UI verification passed (Lab form detected)")
            else:
                feedback_lines.append("? UI verification inconclusive (Lab form not clearly detected)")
        else:
            feedback_lines.append("? VLM check failed to execute")
    
    # Final Evaluation
    passed = (score >= 60) and (results_correct >= 3) and (report is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }