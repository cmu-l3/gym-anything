#!/usr/bin/env python3
"""
Verifier for document_problem_rca task.
Checks if the agent correctly documented Root Cause, Symptoms, and Workaround.
"""

import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_problem_rca(traj, env_info, task_info):
    """
    Verify the problem documentation task.
    
    Success Criteria:
    1. Root Cause text contains key technical details.
    2. Symptoms text contains specific error codes.
    3. Workaround/Solution text contains actionable steps.
    4. VLM confirms UI navigation to Analysis/Solution tabs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rca_kw = metadata.get('expected_rca_keywords', ["Deadlock", "Weekly_Audit_Report"])
    expected_sym_kw = metadata.get('expected_symptom_keywords', ["500", "SQLSTATE"])
    expected_wa_kw = metadata.get('expected_workaround_keywords', ["Restart", "PayrollService"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data from API or DB fallback
    api_analysis = result.get("api_data", {}).get("analysis", {})
    api_solution = result.get("api_data", {}).get("solution", {})
    db_raw_rca = result.get("db_data", {}).get("rca_raw", "")
    db_raw_sol = result.get("db_data", {}).get("sol_raw", "")
    
    # Normalize text for checking
    # We combine API and DB fields to be robust (if API missed it but DB captured it)
    rca_text = (str(api_analysis.get("root_cause", "")) + " " + db_raw_rca).lower()
    sym_text = (str(api_analysis.get("symptoms", "")) + " " + db_raw_rca).lower()
    wa_text = (str(api_solution.get("description", "")) + " " + str(api_solution.get("workaround", "")) + " " + db_raw_sol).lower()

    # 1. Verify Root Cause (30 pts)
    rca_hits = [kw for kw in expected_rca_kw if kw.lower() in rca_text]
    if len(rca_hits) >= 2:
        score += 30
        feedback_parts.append(f"Root Cause verified ({len(rca_hits)}/{len(expected_rca_kw)} keywords)")
    elif len(rca_hits) == 1:
        score += 15
        feedback_parts.append("Root Cause partially verified")
    else:
        feedback_parts.append("Root Cause missing or incorrect")

    # 2. Verify Symptoms (30 pts)
    sym_hits = [kw for kw in expected_sym_kw if kw.lower() in sym_text]
    if len(sym_hits) >= len(expected_sym_kw) - 1: # Allow missing 1
        score += 30
        feedback_parts.append("Symptoms verified")
    elif len(sym_hits) > 0:
        score += 15
        feedback_parts.append("Symptoms partially verified")
    else:
        feedback_parts.append("Symptoms missing")

    # 3. Verify Workaround (30 pts)
    wa_hits = [kw for kw in expected_wa_kw if kw.lower() in wa_text]
    if len(wa_hits) >= 2:
        score += 30
        feedback_parts.append("Workaround verified")
    elif len(wa_hits) > 0:
        score += 15
        feedback_parts.append("Workaround partially verified")
    else:
        feedback_parts.append("Workaround missing")

    # 4. VLM Verification (10 pts)
    # Check if agent visited Analysis/Solution tabs
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Did the user navigate to the 'Analysis' or 'Solutions' tab in the ServiceDesk Plus interface? "
        "Does the interface show text being entered into fields like Root Cause, Symptoms, or Workaround?"
    )
    
    vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    if vlm_res.get("success") and "yes" in vlm_res.get("parsed", {}).get("answer", "").lower():
        score += 10
        feedback_parts.append("VLM: Workflow confirmed")
    else:
        # Fallback: if text verification passed perfectly, give VLM points anyway
        if score >= 90:
            score += 10
            feedback_parts.append("VLM: Implicit pass (text correct)")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }