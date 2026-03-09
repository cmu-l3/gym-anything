#!/usr/bin/env python3
"""
Verifier for Blue Sky Plan sinus evaluation task.

Verification Strategy:
1. Report Verification:
   - Check if report file exists and was created during task.
   - Extract measurements for #3 and #14.
   - Extract clinical decisions.
   - Compare measurements to Ground Truth (tolerance +/- 3mm).
   - Verify logic (e.g., if <10mm, expected "sinus lift").
2. VLM Verification:
   - Check trajectory frames for:
     - Navigation to posterior maxilla (cross-sectional view).
     - Use of linear measurement tool.
     - Measurement orientation (vertical).
"""

import json
import re
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_values(content):
    """
    Extracts bone height measurements and decisions from report text.
    Expected format is loosely structured, so we use regex.
    """
    results = {
        "pos_3_mm": None,
        "pos_14_mm": None,
        "pos_3_decision": "",
        "pos_14_decision": ""
    }
    
    if not content:
        return results

    # Normalize content
    text = content.lower()
    
    # Regex for measurements: looks for "3" or "14" followed eventually by a number
    # This is a heuristic; might need refinement based on exact student output patterns
    
    # Position 3
    # Look for "3" then a float
    m3 = re.search(r'(?:#|pos|position|site)\s*?3.*?(\d{1,2}(?:\.\d{1,2})?)', text)
    if m3:
        try:
            results["pos_3_mm"] = float(m3.group(1))
        except ValueError:
            pass
            
    # Position 14
    m14 = re.search(r'(?:#|pos|position|site)\s*?14.*?(\d{1,2}(?:\.\d{1,2})?)', text)
    if m14:
        try:
            results["pos_14_mm"] = float(m14.group(1))
        except ValueError:
            pass
            
    # Decisions (looking for keywords near the site reference is hard with simple regex,
    # so we just check if the keywords exist in the text generally or try to split by line)
    
    lines = text.splitlines()
    for line in lines:
        if "3" in line:
            if "lift" in line: results["pos_3_decision"] = "lift"
            elif "standard" in line or "sufficient" in line: results["pos_3_decision"] = "standard"
        if "14" in line:
            if "lift" in line: results["pos_14_decision"] = "lift"
            elif "standard" in line or "sufficient" in line: results["pos_14_decision"] = "standard"
            
    return results

def verify_sinus_evaluation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from Windows path (handled by copy_from_env mapping)
    # The environment maps C:\tmp in VM to a path we can access, or we use the copy tool
    # Assuming standard path mapping: /tmp/task_result.json corresponds to C:\tmp\task_result.json
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Depending on implementation, copy_from_env might need the internal path
        # In this env, we assume Unix-like path mapping for the copy tool or providing the Windows path
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- 1. Report Existence and Validity (30 pts) ---
    report_exists = result.get("report_exists", False)
    created_during = result.get("report_created_during_task", False)
    
    if report_exists:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")
        
    if created_during:
        score += 20
        feedback.append("Report was created during the task session.")
    elif report_exists:
        feedback.append("Report file has stale timestamp (anti-gaming failure).")

    # --- 2. Measurement Accuracy (40 pts) ---
    content = result.get("report_content", "")
    parsed = parse_report_values(content)
    ground_truth = result.get("ground_truth", {})
    
    gt_3 = ground_truth.get("pos_3_height_mm", 8.5)
    gt_14 = ground_truth.get("pos_14_height_mm", 12.2)
    tolerance = task_info.get("metadata", {}).get("tolerance_mm", 3.0)
    
    # Verify Pos 3
    if parsed["pos_3_mm"] is not None:
        delta = abs(parsed["pos_3_mm"] - gt_3)
        if delta <= tolerance:
            score += 15
            feedback.append(f"Position #3 measurement ({parsed['pos_3_mm']}mm) is accurate (GT: {gt_3}mm).")
        else:
            feedback.append(f"Position #3 measurement ({parsed['pos_3_mm']}mm) deviates from ground truth ({gt_3}mm).")
            
        # Verify Logic for #3 (GT 8.5mm -> Lift)
        if parsed["pos_3_mm"] < 10.0 and parsed["pos_3_decision"] == "lift":
            score += 5
            feedback.append("Position #3 clinical decision correct (Sinus lift).")
        elif parsed["pos_3_mm"] >= 10.0 and parsed["pos_3_decision"] == "standard":
             score += 5
             feedback.append("Position #3 clinical decision correct (Standard).")
    else:
        feedback.append("Could not parse measurement for Position #3.")

    # Verify Pos 14
    if parsed["pos_14_mm"] is not None:
        delta = abs(parsed["pos_14_mm"] - gt_14)
        if delta <= tolerance:
            score += 15
            feedback.append(f"Position #14 measurement ({parsed['pos_14_mm']}mm) is accurate (GT: {gt_14}mm).")
        else:
            feedback.append(f"Position #14 measurement ({parsed['pos_14_mm']}mm) deviates from ground truth ({gt_14}mm).")
            
        # Verify Logic for #14 (GT 12.2mm -> Standard)
        if parsed["pos_14_mm"] >= 10.0 and parsed["pos_14_decision"] == "standard":
            score += 5
            feedback.append("Position #14 clinical decision correct (Standard).")
        elif parsed["pos_14_mm"] < 10.0 and parsed["pos_14_decision"] == "lift":
            score += 5
            feedback.append("Position #14 clinical decision correct (Sinus lift).")
    else:
        feedback.append("Could not parse measurement for Position #14.")

    # --- 3. VLM Trajectory Verification (30 pts) ---
    # We check if the agent actually navigated to cross-sections and used the ruler
    frames = sample_trajectory_frames(traj, n=5)
    vlm_prompt = (
        "Analyze these screenshots from a dental implant planning software (Blue Sky Plan).\n"
        "1. Do you see a cross-sectional view (showing a slice of the jaw bone)?\n"
        "2. Is the user using a linear measurement ruler tool (a line with a number next to it)?\n"
        "3. Are they measuring the vertical height of the bone (from top of crest to bottom of sinus)?\n"
        "Return JSON: { 'cross_section_visible': bool, 'measurement_tool_used': bool, 'vertical_measurement': bool }"
    )
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        vlm_data = vlm_result.get("parsed", {})
        if vlm_data.get("cross_section_visible"):
            score += 10
            feedback.append("VLM confirmed cross-sectional view usage.")
        if vlm_data.get("measurement_tool_used"):
            score += 10
            feedback.append("VLM confirmed measurement tool usage.")
        if vlm_data.get("vertical_measurement"):
            score += 10
            feedback.append("VLM confirmed vertical bone height measurement.")
    else:
        feedback.append("VLM verification skipped or failed.")

    passed = score >= 60 and report_exists and created_during
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }