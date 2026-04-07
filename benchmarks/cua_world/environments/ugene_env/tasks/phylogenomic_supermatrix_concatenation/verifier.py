#!/usr/bin/env python3
"""
Verifier for phylogenomic_supermatrix_concatenation task.

This relies on programmatic JSON outputs processed by the export shell script,
alongside VLM trajectory checks to ensure the application was utilized.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_supermatrix_concatenation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve results JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse results JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Individual Alignments (30 points)
    if result.get("reca_has_5_taxa", False) and result.get("reca_len", 0) > 0:
        score += 15
        feedback_parts.append(f"recA aligned correctly (length: {result.get('reca_len')})")
    else:
        feedback_parts.append("recA alignment missing or invalid")

    if result.get("rpob_has_5_taxa", False) and result.get("rpob_len", 0) > 0:
        score += 15
        feedback_parts.append(f"rpoB aligned correctly (length: {result.get('rpob_len')})")
    else:
        feedback_parts.append("rpoB alignment missing or invalid")

    # 2. Supermatrix Exists and Contains 5 Taxa (10 points)
    if result.get("superm_has_5_taxa", False):
        score += 10
        feedback_parts.append("Supermatrix has correct number of taxa (5)")
    else:
        feedback_parts.append("Supermatrix missing or has incorrect taxon count (detecting naive file appending)")

    # 3. Supermatrix Created During Task [Anti-gaming] (10 points)
    if result.get("created_during_task", False):
        score += 10
        feedback_parts.append("Supermatrix created during task session")
    else:
        feedback_parts.append("Supermatrix appears to be stale or unmodified")

    # 4. Matrix Math Verification [Anti-gaming] (20 points)
    if result.get("matrix_math_valid", False):
        score += 20
        feedback_parts.append("Matrix mathematics valid (supermatrix len == recA len + rpoB len)")
    else:
        feedback_parts.append("Matrix mathematics invalid (lengths do not sum correctly)")

    # 5. Horizontal Concatenation Integrity [Anti-gaming] (20 points)
    if result.get("horizontal_valid", False):
        score += 20
        feedback_parts.append("Horizontal concatenation verified (Sequences correctly appended per taxon)")
    else:
        feedback_parts.append("Horizontal integrity failed (Sequences not correctly joined)")

    # 6. Report Completed Correctly (10 points)
    if result.get("report_ok", False):
        score += 10
        feedback_parts.append("Summary report includes correct taxa and matching lengths")
    else:
        feedback_parts.append("Summary report missing required taxa or correct alignment lengths")

    # Check VLM Trajectory (Supplemental, doesn't add points but can verify GUI usage if needed)
    # This prevents users from writing a python script to manually execute concatenation inside the VM shell.
    vlm_feedback = ""
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """
                Check these trajectory frames from a user operating the UGENE application.
                Did the user open or use the "Concatenate alignments" dialog tool?
                You should see a dialog box for combining or concatenating alignment files.
                Reply ONLY with 'yes' or 'no'.
                """
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                if vlm_resp and 'yes' in vlm_resp.get("response", "").lower():
                    vlm_feedback = " [VLM confirmed UGENE GUI tool usage]"
                else:
                    vlm_feedback = " [VLM did not detect UGENE GUI tool usage]"
        except Exception:
            pass
            
    # Calculate Pass Status
    # Passing requires >70 and explicit confirmation of horizontal sequence joining.
    horizontal_passed = result.get("horizontal_valid", False)
    passed = score >= 70 and horizontal_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + vlm_feedback
    }