#!/usr/bin/env python3
"""
Verifier for record_compliance_effectiveness task.

Task: Update ISO 27001 Control A.11.2.8 to "Compliant" with specific evidence and review date.

Scoring Criteria:
1. Compliance Status: Must be 'Compliant' (1) (30 pts)
2. Evidence: Must contain 'Workstation Security_v2' and '900s' (30 pts)
3. Schedule: Review date must be '2026-06-30' (20 pts)
4. Anti-Gaming: Record modified during task window (10 pts)
5. VLM Verification: Visual confirmation of workflow (10 pts)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_compliance_effectiveness(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
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

    # Extract data
    db_status = str(result.get('status', '')).strip()
    findings = str(result.get('findings', '')).strip()
    review_date = str(result.get('review_date', '')).strip()
    modified_ts = int(result.get('modified_timestamp', 0) or 0)
    task_start = int(result.get('task_start_time', 0) or 0)
    
    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Criterion 1: Compliance Status (30 pts)
    # ----------------------------------------------------------------
    # Eramba usually uses 1 for Compliant/Yes/OK. Adjust if schema differs.
    # We accept '1', 'Compliant', 'Pass'.
    if db_status in ['1', 'Compliant', 'Pass', 'Yes']:
        score += 30
        feedback.append("Status correctly set to Compliant.")
    else:
        feedback.append(f"Incorrect status: '{db_status}' (Expected Compliant/1)")

    # ----------------------------------------------------------------
    # Criterion 2: Evidence Documentation (30 pts)
    # ----------------------------------------------------------------
    required_strings = ["Workstation Security_v2", "900s"]
    missing_evidence = [s for s in required_strings if s.lower() not in findings.lower()]
    
    if not missing_evidence:
        score += 30
        feedback.append("Evidence documentation is correct.")
    else:
        # Partial credit logic could go here, but binary for simplicity
        if len(missing_evidence) < len(required_strings):
            score += 15
            feedback.append(f"Partial evidence found. Missing: {missing_evidence}")
        else:
            feedback.append(f"Evidence missing required details: {missing_evidence}")

    # ----------------------------------------------------------------
    # Criterion 3: Review Schedule (20 pts)
    # ----------------------------------------------------------------
    # Note: DB might return date time or just date. We check if string contains the date.
    if "2026-06-30" in review_date:
        score += 20
        feedback.append("Next review date correctly set.")
    else:
        feedback.append(f"Incorrect review date: '{review_date}' (Expected 2026-06-30)")

    # ----------------------------------------------------------------
    # Criterion 4: Anti-Gaming / Modification Check (10 pts)
    # ----------------------------------------------------------------
    if modified_ts > task_start:
        score += 10
        feedback.append("Record verified as modified during task.")
    else:
        feedback.append("Record was NOT modified during the task (timestamp check failed).")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Verification (10 pts)
    # ----------------------------------------------------------------
    # Use trajectory to verify the user actually interacted with the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from a GRC software (Eramba).
    Did the user:
    1. Navigate to a Compliance Analysis or Compliance Package screen?
    2. Open a form to edit/assess a control?
    3. Enter text related to "Workstation Security" or "900s"?
    
    Answer YES or NO with a brief reason.
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    
    if "YES" in vlm_result.get('response', '').upper():
        score += 10
        feedback.append("VLM verified UI workflow.")
    else:
        feedback.append(f"VLM did not verify workflow: {vlm_result.get('response', 'No response')}")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Pass threshold: 70 points (Must get Status + Evidence correct + some other factor)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }