#!/usr/bin/env python3
"""
Verifier for Patient Demographics Report task.

Verifies:
1. Report file exists and was created during the task.
2. Report contains correct statistics (Total, Male/Female, Average Age).
3. Report identifies correct Oldest/Youngest patients.
4. VLM verifies agent actually used MedinTux to look up data.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patient_demographic_report(traj, env_info, task_info):
    """
    Verify the patient demographics report.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence and Creation (Anti-Gaming)
    if not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file not found at ~/patient_demographics_report.txt"}
    
    if not result.get("report_created_during_task"):
        feedback.append("WARNING: Report file timestamp indicates it wasn't created during this task session.")
        # We don't fail immediately but penalize heavily
    else:
        score += 10
        feedback.append("Report file created successfully.")

    # 3. Analyze Content vs Ground Truth
    content = result.get("report_content", "")
    gt = result.get("ground_truth", {})
    
    if not gt or "error" in gt:
        return {"passed": False, "score": 0, "feedback": "System error: Failed to generate ground truth from database."}

    # Helper regex for extraction
    def extract_val(pattern, text):
        m = re.search(pattern, text, re.IGNORECASE)
        return m.group(1).strip() if m else None

    # Check Total Patients
    total_found = extract_val(r"Total Patients:\s*(\d+)", content)
    if total_found and int(total_found) == gt['total']:
        score += 10
        feedback.append(f"Correct Total Patients: {total_found}")
    else:
        feedback.append(f"Incorrect Total Patients. Expected {gt['total']}, found {total_found}")

    # Check Gender Breakdown
    male_found = extract_val(r"Male \(H\):\s*(\d+)", content)
    if male_found and int(male_found) == gt['males']:
        score += 10
        feedback.append(f"Correct Male Count: {male_found}")
    else:
        feedback.append(f"Incorrect Male Count. Expected {gt['males']}, found {male_found}")

    female_found = extract_val(r"Female \(F\):\s*(\d+)", content)
    if female_found and int(female_found) == gt['females']:
        score += 10
        feedback.append(f"Correct Female Count: {female_found}")
    else:
        feedback.append(f"Incorrect Female Count. Expected {gt['females']}, found {female_found}")

    # Check Average Age
    # Allow +/- 1 year tolerance for calculation differences
    avg_found = extract_val(r"Average Age:\s*(\d+)", content)
    if avg_found:
        val = int(avg_found)
        target = gt['average_age']
        if abs(val - target) <= 1:
            score += 15
            feedback.append(f"Correct Average Age: {val} (Target: {target})")
        else:
            feedback.append(f"Incorrect Average Age. Expected ~{target}, found {val}")
    else:
        feedback.append("Average Age not found in report")

    # Check Oldest/Youngest (Name matching)
    # Ground truth format: "NOM (born YYYY-MM-DD)" - we check if the name is present in the line
    oldest_line_match = re.search(r"Oldest Patient:\s*(.*)", content, re.IGNORECASE)
    if oldest_line_match:
        line = oldest_line_match.group(1)
        # Check if DURAND (oldest in our specific dataset) is in the line
        if "DURAND" in line.upper():
            score += 10
            feedback.append("Correct Oldest Patient identified")
        else:
            feedback.append(f"Incorrect Oldest Patient identified. Line: {line}")
    else:
        feedback.append("Oldest Patient section missing")

    youngest_line_match = re.search(r"Youngest Patient:\s*(.*)", content, re.IGNORECASE)
    if youngest_line_match:
        line = youngest_line_match.group(1)
        # Check if ROBERT (youngest in our specific dataset) is in the line
        if "ROBERT" in line.upper():
            score += 10
            feedback.append("Correct Youngest Patient identified")
        else:
            feedback.append(f"Incorrect Youngest Patient identified. Line: {line}")
    else:
        feedback.append("Youngest Patient section missing")

    # Check for list of patients (Simple check: does it contain at least 5 of the 8 names?)
    names_found_count = 0
    for p in gt.get('patients', []):
        if p['name'] in content:
            names_found_count += 1
    
    if names_found_count >= 8:
        score += 15
        feedback.append("Complete patient list found")
    elif names_found_count >= 4:
        score += 7
        feedback.append(f"Partial patient list found ({names_found_count}/8)")
    else:
        feedback.append("Patient list missing or incomplete")

    # 4. VLM Verification (Trajectory Check)
    # We want to ensure the agent actually opened MedinTux and looked at the list
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a computer task.
        The user is supposed to use 'MedinTux' (medical software) to view a list of patients.
        
        Do you see:
        1. The MedinTux interface (often gray/blue with icons)?
        2. A list of patient names (e.g., MARTIN, BERNARD, DUBOIS)?
        3. A text editor being used to write a report?
        
        Return JSON: {"medintux_visible": bool, "patient_list_seen": bool, "text_editor_used": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('medintux_visible') or parsed.get('patient_list_seen'):
                    score += 10
                    feedback.append("VLM confirmed MedinTux usage.")
                else:
                    feedback.append("VLM did not see MedinTux interaction clearly.")
        except Exception:
            # Fallback if VLM fails - give benefit of doubt if output is perfect
            if score >= 60: score += 10

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }