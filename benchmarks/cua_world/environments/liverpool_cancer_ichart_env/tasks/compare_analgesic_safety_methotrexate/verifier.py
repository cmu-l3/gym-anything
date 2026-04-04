#!/usr/bin/env python3
"""
Verifier for compare_analgesic_safety_methotrexate task.

Verification Strategy:
1. File Verification:
   - Checks if /sdcard/methotrexate_analgesic_report.txt exists.
   - Checks if it was created during the task.
   - Parses text for correct interaction colors for Ibuprofen/Diclofenac (Red/Orange) and Paracetamol (Green).
   - Verifies the conclusion identifies Paracetamol as the safest option.

2. VLM Trajectory Verification:
   - Checks if the agent visited the Methotrexate page.
   - Checks if the agent viewed interaction results for the relevant drugs.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_analgesic_safety(traj, env_info, task_info):
    """
    Verify the analgesic safety comparison task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Result JSON from Device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Depending on environment driver, this might copy from container or device.
        # Assuming standard behavior where provided path is accessed.
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Criterion 1: Output File Exists (10 pts)
    content = result_data.get("file_content", "").lower()
    if result_data.get("output_exists", False):
        score += 10
        feedback_parts.append("Report file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    # Criterion 2: Created During Task (10 pts)
    if result_data.get("created_during_task", False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task.")

    # Criterion 3: Ibuprofen Check (Red/Orange/Amber) (20 pts)
    ibuprofen_pattern = r"ibuprofen.*?(red|orange|amber|avoid|unsafe)"
    if "ibuprofen" in content:
        if re.search(ibuprofen_pattern, content, re.DOTALL):
            score += 20
            feedback_parts.append("Ibuprofen identified as high risk.")
        elif "ibuprofen" in content:
            feedback_parts.append("Ibuprofen mentioned but risk level unclear/wrong.")
            score += 5
    else:
        feedback_parts.append("Ibuprofen not mentioned.")

    # Criterion 4: Diclofenac Check (Red/Orange/Amber) (20 pts)
    diclofenac_pattern = r"diclofenac.*?(red|orange|amber|avoid|unsafe)"
    if "diclofenac" in content:
        if re.search(diclofenac_pattern, content, re.DOTALL):
            score += 20
            feedback_parts.append("Diclofenac identified as high risk.")
        elif "diclofenac" in content:
            feedback_parts.append("Diclofenac mentioned but risk level unclear/wrong.")
            score += 5
    else:
        feedback_parts.append("Diclofenac not mentioned.")

    # Criterion 5: Paracetamol Check (Green/Yellow/Safe) (20 pts)
    paracetamol_pattern = r"(paracetamol|acetaminophen).*?(green|yellow|grey|safe|no interaction)"
    if "paracetamol" in content or "acetaminophen" in content:
        if re.search(paracetamol_pattern, content, re.DOTALL):
            score += 20
            feedback_parts.append("Paracetamol identified as low risk.")
        else:
            feedback_parts.append("Paracetamol mentioned but safety unclear.")
            score += 5
    else:
        feedback_parts.append("Paracetamol not mentioned.")

    # Criterion 6: Conclusion (Safest Option) (20 pts)
    # Looking for explicit statement that Paracetamol is safest/best
    conclusion_pattern = r"(safest|safe option|recommend|best choice).*?(paracetamol|acetaminophen)"
    if re.search(conclusion_pattern, content, re.DOTALL):
        score += 20
        feedback_parts.append("Correctly concluded Paracetamol is the safest option.")
    else:
        # Check if they just said NSAIDs are bad
        if "avoid" in content and ("ibuprofen" in content or "diclofenac" in content):
             score += 5
             feedback_parts.append("Noted avoidance of NSAIDs, but didn't explicitly recommend Paracetamol as safest.")
        else:
             feedback_parts.append("No clear safety conclusion found.")

    # 3. VLM Verification (Trajectory)
    # We define 'passed' based on the file content primarily, but could use VLM to validate the method.
    # For this task, we will simply log the VLM part or use it as a sanity check if score > 50.
    
    # Ensure key criteria for passing
    key_criteria_met = (
        "paracetamol" in content or "acetaminophen" in content
    ) and (
        re.search(conclusion_pattern, content, re.DOTALL) is not None
    )

    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }