#!/usr/bin/env python3
"""
Verifier for add_case_costs task.

Verifies:
1. API Data: 3 cost entries exist with correct amounts and descriptions.
2. Report File: Created during task, contains summary and correct total.
3. VLM (Optional): Trajectory verification.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_case_costs(traj, env_info, task_info):
    """
    Verify that case costs were added correctly and report saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_entries = metadata.get('expected_entries', [])
    expected_total = metadata.get('expected_total', 2025.00)

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []

    # ------------------------------------------------------------------
    # Criteria 1: API Verification (60 Points)
    # ------------------------------------------------------------------
    api_costs = result.get('api_data', {}).get('costs', [])
    
    # Ensure api_costs is a list
    if not isinstance(api_costs, list):
        api_costs = []

    # Check count
    if len(api_costs) >= 3:
        score += 10
        feedback.append("Correct number of cost entries found (>=3).")
    else:
        feedback.append(f"Found {len(api_costs)} cost entries, expected 3.")

    # Check specific entries
    # We try to match each expected entry to one in the API results
    matches = 0
    total_amount_found = 0.0
    
    for entry in api_costs:
        # Normalize fields (ArkCase might use 'amount', 'cost', 'value', 'description', 'title')
        amt = float(entry.get('amount') or entry.get('cost') or entry.get('value') or 0)
        desc = str(entry.get('description') or entry.get('title') or entry.get('notes') or "").lower()
        total_amount_found += amt
        
        # Check against expected
        for exp in expected_entries:
            exp_amt = float(exp['amount'])
            exp_desc = str(exp['description']).lower()
            
            # Allow slight fuzzy match on description and exact match on amount
            if abs(amt - exp_amt) < 0.01 and (exp_desc in desc or desc in exp_desc):
                matches += 1
                break
    
    # Score based on matches (Max 40 points here: 15 per entry approx)
    # 3 matches = 40 pts, 2 = 25 pts, 1 = 10 pts
    if matches >= 3:
        score += 40
        feedback.append("All 3 cost entries match expected amounts and descriptions.")
    elif matches == 2:
        score += 25
        feedback.append("2 cost entries match expectations.")
    elif matches == 1:
        score += 10
        feedback.append("1 cost entry matches expectations.")
    else:
        feedback.append("No cost entries matched specific amount/description pairs.")

    # Check total
    if abs(total_amount_found - expected_total) < 0.01:
        score += 10
        feedback.append(f"Total cost verified via API: ${total_amount_found:.2f}")
    else:
        feedback.append(f"Total cost mismatch. Found: ${total_amount_found:.2f}, Expected: ${expected_total:.2f}")

    # ------------------------------------------------------------------
    # Criteria 2: Report File Verification (20 Points)
    # ------------------------------------------------------------------
    report = result.get('report_file', {})
    if report.get('exists'):
        score += 5
        feedback.append("Report file exists.")
        
        if report.get('created_during_task'):
            score += 5
            feedback.append("Report created during task.")
        
        content = report.get('content_snippet', "").lower()
        if str(int(expected_total)) in content or str(expected_total) in content:
            score += 10
            feedback.append("Report contains correct total.")
    else:
        feedback.append("Report file not found.")

    # ------------------------------------------------------------------
    # Criteria 3: VLM Verification (20 Points)
    # ------------------------------------------------------------------
    # Only run VLM if we haven't already failed drastically or if we need confirmation
    # If API confirmed everything, we trust it mostly, but VLM adds robustness against direct DB manipulation
    
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if frames and final_img:
        prompt = """
        Analyze this sequence of screenshots from a case management task.
        1. Did the user navigate to a 'Costs', 'Expenses', or 'Financials' tab/section?
        2. Do you see a list of cost items being added or displayed?
        3. Is there a final view showing a total around $2,025?
        
        Return JSON: {"navigated_to_costs": bool, "entries_visible": bool, "total_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_img], prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            if vlm_data.get('navigated_to_costs'):
                vlm_score += 10
            if vlm_data.get('entries_visible'):
                vlm_score += 10
                
            score += vlm_score
            if vlm_score > 0:
                feedback.append(f"VLM verified visual workflow ({vlm_score} pts).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if API passed, give full points. If API failed, give 0.
            if score >= 50:
                score += 20
                feedback.append("VLM skipped, awarded points based on API success.")

    # ------------------------------------------------------------------
    # Final Calculation
    # ------------------------------------------------------------------
    passed = score >= 60 and matches >= 2 # Require at least 2 correct entries for pass
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }