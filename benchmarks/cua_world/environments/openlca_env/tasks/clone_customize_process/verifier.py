#!/usr/bin/env python3
"""
Verifier for Clone & Customize Process task.

Verification Logic:
1.  **Database Check (30 pts):**
    -   Database must exist and contain processes.
    -   A new process with "Facility", "Site", or "XYZ" in the name must exist.
2.  **Report File Check (30 pts):**
    -   File `process_customization_report.csv` must exist.
    -   Must be created during the task.
    -   Must contain relevant keywords (Electricity, Gas/Fuel).
3.  **Data Accuracy Check (20 pts):**
    -   Parse numbers from the report.
    -   Verify if any pair of numbers represents a ~20% reduction (Electricity).
    -   Verify if any pair of numbers represents a ~12% reduction (Fuel).
4.  **VLM Workflow Check (20 pts):**
    -   Verify trajectory shows process duplication/copying.
    -   Verify parameter/exchange editing.

Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def check_reduction(text_content, reduction_target, tolerance=0.05):
    """
    Scans text for pairs of numbers (a, b) where b is approx (1-target) * a.
    Returns True if found.
    """
    # Extract all floating point numbers
    numbers = [float(x) for x in re.findall(r'-?\d+\.?\d*', text_content)]
    if len(numbers) < 2:
        return False
    
    target_ratio = 1.0 - reduction_target
    
    # Check all pairs (assuming standard report format: Original, New)
    # We check neighbor pairs and row-aligned pairs roughly
    for i in range(len(numbers)):
        for j in range(len(numbers)):
            if i == j: continue
            
            val_a = numbers[i]
            val_b = numbers[j]
            
            if val_a == 0: continue
            
            ratio = val_b / val_a
            
            # Check if ratio is close to target (e.g. 0.8 for 20% reduction)
            if abs(ratio - target_ratio) < tolerance:
                return True
                
    return False

def verify_clone_customize_process(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database Check (30 pts)
    db_found = result.get('db_found', False)
    new_proc_found = result.get('new_process_found', False)
    
    if db_found:
        score += 10
        if new_proc_found:
            score += 20
            feedback.append(f"New facility process found: {result.get('new_process_name')}")
        else:
            feedback.append("Database found, but no process named 'Facility/Site/XYZ' found")
    else:
        feedback.append("No valid database found")

    # 2. Report File Check (30 pts)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "")
    
    if report_exists:
        score += 10
        if result.get('file_created_during_task', False):
            score += 10
            feedback.append("Report created during task")
        
        # Check keywords
        if "electr" in report_content.lower() or "gas" in report_content.lower() or "fuel" in report_content.lower():
            score += 10
            feedback.append("Report contains expected keywords")
        else:
            feedback.append("Report missing keywords (Electricity/Gas)")

    # 3. Data Accuracy Check (20 pts)
    # 20% reduction (0.8 ratio) and 12% reduction (0.88 ratio)
    elec_check = check_reduction(report_content, 0.20)
    fuel_check = check_reduction(report_content, 0.12)
    
    if elec_check:
        score += 10
        feedback.append("Verified ~20% reduction in report data")
    
    if fuel_check:
        score += 10
        feedback.append("Verified ~12% reduction in report data")

    # 4. VLM Check (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 4)
        
        prompt = """Analyze these screenshots of an openLCA user.
        Look for:
        1. A process list or navigation tree being used.
        2. A 'Copy' / 'Paste' or 'Save As' action (creating a duplicate).
        3. An input/output exchange table being edited (numbers being changed).
        
        Return JSON:
        {
            "copy_action_observed": true/false,
            "editing_exchanges": true/false
        }
        """
        vlm_res = _vlm_query(query_vlm, prompt, images=frames)
        if vlm_res:
            if vlm_res.get("copy_action_observed"):
                score += 10
            if vlm_res.get("editing_exchanges"):
                score += 10

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }