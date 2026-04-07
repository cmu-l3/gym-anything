#!/usr/bin/env python3
"""
Verifier for register_facility_log_incident task.

Verifies:
1. Facility "Westside Cold Storage" exists in DB.
2. Incident record linked to facility exists in DB with correct details (Date, Description).
3. PDF Report was generated and saved to correct location.
4. VLM verification of UI workflow.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_facility_log_incident(traj, env_info, task_info):
    """
    Verify the facility registration and incident logging task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported result from container
    # The export_result.ps1 saves to C:\tmp\task_result.json, which is inside the container
    # We map this path for copy_from_env. 
    # Note: copy_from_env usually expects Unix-style paths for Linux containers, 
    # but for Windows containers it might expect C:/... or just /tmp/... depending on implementation.
    # Assuming standard path handling.
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try Windows path style first
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from environment."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # === Criteria 1: PDF Generation (20 pts) ===
    pdf_exists = result.get("pdf_exists", False)
    pdf_fresh = result.get("pdf_created_during_task", False)
    
    if pdf_exists and pdf_fresh:
        score += 20
        feedback_parts.append("PDF report generated successfully.")
    elif pdf_exists:
        score += 10
        feedback_parts.append("PDF report exists but timestamp is old (reused file?).")
    else:
        feedback_parts.append("PDF report NOT found.")

    # === Criteria 2: Database Verification (40 pts) ===
    fac_found = result.get("facility_record_found", False)
    inc_found = result.get("incident_record_found", False)
    data_correct = result.get("incident_data_correct", False)
    
    if fac_found:
        score += 10
        feedback_parts.append("Facility record verified in database.")
    else:
        feedback_parts.append("Facility record missing.")
        
    if inc_found:
        score += 10
        feedback_parts.append("Incident record linked to facility.")
    else:
        feedback_parts.append("Incident record missing or not linked.")
        
    if data_correct:
        score += 20
        feedback_parts.append("Incident details (Date, Description) match requirements.")
    else:
        if inc_found:
            feedback_parts.append("Incident data mismatch (wrong date or description).")

    # === Criteria 3: VLM Workflow Verification (40 pts) ===
    # Check if agent visited both modules and performed actions
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No trajectory frames available for VLM verification.")
    else:
        prompt = """
        Analyze these screenshots of CAMEO Data Manager.
        
        I need to verify if the user performed these specific actions:
        1. Accessed the 'Facilities' module (look for 'Facilities' window title or tabs).
        2. Accessed the 'Incidents' module (look for 'Incidents' window title or tabs).
        3. Entered data related to 'Westside Cold Storage' or 'Ammonia'.
        4. Generated a report (Print dialog or Report preview).
        
        Return JSON:
        {
            "visited_facilities": true/false,
            "visited_incidents": true/false,
            "data_entry_visible": true/false,
            "report_generation_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=frames)
        vlm_data = vlm_resp.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("visited_facilities"): vlm_score += 10
        if vlm_data.get("visited_incidents"): vlm_score += 10
        if vlm_data.get("data_entry_visible"): vlm_score += 10
        if vlm_data.get("report_generation_visible"): vlm_score += 10
        
        score += vlm_score
        feedback_parts.append(f"VLM verified workflow steps ({vlm_score}/40 pts).")

    # Final logic
    key_requirements = pdf_exists and fac_found and inc_found
    passed = (score >= 70) and key_requirements
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }