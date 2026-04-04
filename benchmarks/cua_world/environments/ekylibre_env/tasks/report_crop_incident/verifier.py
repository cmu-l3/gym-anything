#!/usr/bin/env python3
"""
Verifier for Report Crop Incident Task

Criteria:
1. Incident Created: Database count increased (30 pts)
2. Correct Plot: New record linked to 'La Grande Borne' (20 pts)
3. Correct Cause: New record cause is 'Rouille jaune' (20 pts)
4. Correct Severity: New record severity is High (20 pts)
5. VLM Verification: Visual confirmation of workflow (10 pts)
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_report_crop_incident(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
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
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_plot = metadata.get('target_plot_name', 'La Grande Borne')
    target_pest = metadata.get('target_pest_name', 'Rouille jaune')
    
    # Extract Data
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    incident_record = result.get('new_incident_record')

    # Criterion 1: Incident Created (30 pts)
    # Check if count increased OR we found a specific new record
    count_increased = current_count > initial_count
    record_found = incident_record is not None
    
    if count_increased or record_found:
        score += 30
        feedback_parts.append("Incident record created")
    else:
        feedback_parts.append("No new incident record found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Correct Plot (20 pts)
    plot_correct = False
    if record_found:
        zone_name = incident_record.get('zone_name', '')
        if zone_name and target_plot.lower() in zone_name.lower():
            score += 20
            plot_correct = True
            feedback_parts.append(f"Correct plot: {zone_name}")
        else:
            feedback_parts.append(f"Incorrect plot: '{zone_name}' (expected '{target_plot}')")
    
    # Criterion 3: Correct Cause (20 pts)
    cause_correct = False
    if record_found:
        cause_name = incident_record.get('cause_name', '')
        if cause_name and target_pest.lower() in cause_name.lower():
            score += 20
            cause_correct = True
            feedback_parts.append(f"Correct cause: {cause_name}")
        else:
            feedback_parts.append(f"Incorrect cause: '{cause_name}' (expected '{target_pest}')")

    # Criterion 4: Correct Severity (20 pts)
    # Severity in Ekylibre might be integer (0-3) or string ("high").
    # We accept "High", "Importante", "3", or "2" (depending on scale).
    severity_correct = False
    if record_found:
        raw_severity = str(incident_record.get('severity', '')).lower()
        valid_severities = ['high', 'importante', 'élevée', '3', '2'] # 3 is usually critical/high
        if any(v in raw_severity for v in valid_severities):
            score += 20
            severity_correct = True
            feedback_parts.append(f"Correct severity: {raw_severity}")
        else:
            feedback_parts.append(f"Incorrect severity: {raw_severity} (expected High)")

    # Criterion 5: VLM Verification (10 pts)
    # Visual check using trajectory
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = f"""
    The user is performing a task in Ekylibre farm software: "Report a Yellow Rust incident on La Grande Borne plot with High severity".
    
    Look at the screenshots. Did the user:
    1. Navigate to an incident/observation form?
    2. Select 'Rouille jaune' (Yellow Rust)?
    3. Select 'La Grande Borne'?
    4. Save the record?
    
    Return JSON: {{"workflow_followed": boolean, "details": "string"}}
    """
    
    try:
        vlm_res = query_vlm(images, vlm_prompt)
        if vlm_res.get('workflow_followed', False):
            score += 10
            feedback_parts.append("VLM confirmed workflow")
        else:
            feedback_parts.append(f"VLM check failed: {vlm_res.get('details', 'Workflow unclear')}")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: give points if DB record is perfect
        if plot_correct and cause_correct and severity_correct:
            score += 10

    # Final Pass Logic
    # Must have created record AND got at least one key detail right (plot or cause)
    passed = (score >= 70) and (count_increased or record_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }