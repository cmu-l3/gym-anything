#!/usr/bin/env python3
"""
Verifier for chemical_exposure_symptom_diagnosis task.
Checks if the agent correctly identified the chemicals based on symptoms
and provided supporting evidence from the CAMEO datasheets.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_exposure_symptom_diagnosis(traj, env_info, task_info):
    """
    Verify the agent's diagnosis report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', '/home/ga/Documents/exposure_diagnosis_report.txt')
    answers = metadata.get('answers', {})

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check Task Result JSON (File Existence & Timing)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Diagnosis report file not found."}
    
    if not task_result.get("file_created_during_task", False):
        feedback_parts.append("Warning: Output file timestamp is outside task window.")
    else:
        score += 10 # Points for creating the file during task
        feedback_parts.append("File created successfully.")

    # 2. Check Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(expected_output_path, temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read().lower()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Helper to check sections (simple heuristic: split by incident or look for proximity)
    # Since parsing free text is hard, we look for the chemical name and keywords within the whole text 
    # but strictly checking they appear. For a robust check, we assume the agent separates them reasonably.
    
    # Incident A: Hydrogen Sulfide
    inc_a_correct = "hydrogen sulfide" in report_content or "7783-06-4" in report_content
    inc_a_evidence = any(k in report_content for k in answers["Incident A"]["keywords"])
    
    if inc_a_correct:
        score += 20
        feedback_parts.append("Incident A: Correctly identified Hydrogen Sulfide.")
    else:
        feedback_parts.append("Incident A: Failed to identify Hydrogen Sulfide.")
        
    if inc_a_evidence:
        score += 10
        feedback_parts.append("Incident A: Evidence cited correctly (olfactory fatigue/smell).")
    else:
        feedback_parts.append("Incident A: Missing specific evidence about smell/olfactory fatigue.")

    # Incident B: Hydrofluoric Acid
    inc_b_correct = "hydrofluoric acid" in report_content or "7664-39-3" in report_content
    inc_b_evidence = any(k in report_content for k in answers["Incident B"]["keywords"])

    if inc_b_correct:
        score += 20
        feedback_parts.append("Incident B: Correctly identified Hydrofluoric Acid.")
    else:
        feedback_parts.append("Incident B: Failed to identify Hydrofluoric Acid.")

    if inc_b_evidence:
        score += 10
        feedback_parts.append("Incident B: Evidence cited correctly (delayed pain).")
    else:
        feedback_parts.append("Incident B: Missing specific evidence about delayed symptoms.")

    # Incident C: Phenol
    inc_c_correct = "phenol" in report_content or "108-95-2" in report_content or "carbolic acid" in report_content
    inc_c_evidence = any(k in report_content for k in answers["Incident C"]["keywords"])

    if inc_c_correct:
        score += 20
        feedback_parts.append("Incident C: Correctly identified Phenol.")
    else:
        feedback_parts.append("Incident C: Failed to identify Phenol.")

    if inc_c_evidence:
        score += 10
        feedback_parts.append("Incident C: Evidence cited correctly (whitening/numbness).")
    else:
        feedback_parts.append("Incident C: Missing specific evidence about skin whitening or numbness.")

    # 3. VLM Verification (Trajectory Analysis)
    # Check if the agent actually visited CAMEO Chemicals and looked at datasheets
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    if frames:
        vlm_prompt = (
            "Does the user appear to be using the CAMEO Chemicals website? "
            "Do you see chemical datasheets or search results for Hydrogen Sulfide, Hydrofluoric Acid, or Phenol? "
            "Reply with 'YES' or 'NO' and a brief reason."
        )
        # We don't hard fail on VLM, but it confirms work was done
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result and "YES" in vlm_result.get("response", "").upper():
                feedback_parts.append("VLM: Confirmed usage of CAMEO Chemicals.")
            else:
                feedback_parts.append("VLM: Could not clearly confirm CAMEO Chemicals usage from screenshots.")
        except Exception:
            pass # Ignore VLM errors for scoring to avoid brittleness

    passed = score >= 70 and inc_a_correct and inc_b_correct and inc_c_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }