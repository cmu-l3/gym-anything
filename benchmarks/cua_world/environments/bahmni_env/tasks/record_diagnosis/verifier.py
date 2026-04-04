#!/usr/bin/env python3
"""
Verifier for record_diagnosis task.

Checks:
1. Diagnosis 'Malaria' exists with Order=PRIMARY, Certainty=CONFIRMED.
2. Diagnosis 'Anaemia' exists with Order=SECONDARY, Certainty=CONFIRMED.
3. Diagnoses were created AFTER the task started (anti-gaming).
4. VLM verification of the clinical workflow trajectory.
"""

import json
import os
import tempfile
import time
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO8601-like dates (e.g., '2023-10-25T14:30:00.000+0000')."""
    try:
        # Python 3.7+ handles %z
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.000%z")
    except ValueError:
        try:
            # Fallback for different formats if API varies
            return datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
        except:
            return None

def verify_record_diagnosis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result Data
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

    # 2. Parse Data
    task_start_ts = result.get("task_start_time", 0)
    final_diagnoses = result.get("final_diagnoses", [])
    
    # Handle API response wrapper (Bahmni API usually returns list directly, but check wrapper)
    if isinstance(final_diagnoses, dict) and "results" in final_diagnoses:
        final_diagnoses = final_diagnoses["results"]
    
    if not isinstance(final_diagnoses, list):
        final_diagnoses = []

    logger.info(f"Task Start: {task_start_ts}")
    logger.info(f"Found {len(final_diagnoses)} diagnoses")

    # 3. Evaluation Logic
    score = 0
    feedback = []
    
    # Targets
    targets = {
        "Malaria": {"order": "PRIMARY", "certainty": "CONFIRMED", "points": 45, "found": False},
        "Anaemia": {"order": "SECONDARY", "certainty": "CONFIRMED", "points": 45, "found": False}
    }
    
    found_diagnoses_names = []

    for diag in final_diagnoses:
        # Extract fields
        # Bahmni API structure: 
        # { "codedAnswer": { "name": "Malaria" }, "order": "PRIMARY", "certainty": "CONFIRMED", "diagnosisDateTime": "..." }
        
        coded_answer = diag.get("codedAnswer", {})
        name = coded_answer.get("name", "")
        if not name:
            # Sometimes it's directly 'concept'
            name = diag.get("concept", {}).get("name", "")
            
        order = diag.get("order", "").upper()
        certainty = diag.get("certainty", "").upper()
        diag_date_str = diag.get("diagnosisDateTime") or diag.get("encounter", {}).get("encounterDatetime")
        
        # Verify Timestamp (Anti-Gaming)
        if diag_date_str:
            diag_dt = parse_openmrs_date(diag_date_str)
            if diag_dt:
                diag_ts = diag_dt.timestamp()
                # Allow small clock skew (e.g. 5s) or processing time
                if diag_ts < (task_start_ts - 5):
                    continue # Skip old diagnoses
        
        found_diagnoses_names.append(f"{name}({order},{certainty})")

        # Check against targets
        # Partial matching for names (e.g. "Malaria, unspecified" vs "Malaria")
        for target_name, criteria in targets.items():
            if target_name.lower() in name.lower():
                # Name Match found
                
                # Check Metadata
                order_match = (order == criteria["order"])
                certainty_match = (certainty == criteria["certainty"])
                
                if order_match and certainty_match:
                    if not criteria["found"]: # Count once
                        score += criteria["points"]
                        criteria["found"] = True
                        feedback.append(f"Success: Recorded {target_name} ({order}, {certainty}).")
                else:
                    feedback.append(f"Partial: Found {name} but metadata mismatch (Expected {criteria['order']}/{criteria['certainty']}, got {order}/{certainty}).")

    # 4. VLM Verification (Bonus/Confirmation)
    # Using trajectory to verify UI interaction if score is borderline or for completeness
    vlm_points = 10
    vlm_score = 0
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # We sample a few frames to see if they were in the Clinical app
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        Analyze these screenshots of a medical software interface (Bahmni).
        1. Is the user in a 'Clinical' or 'Consultation' view?
        2. Is there a 'Diagnoses' section visible where medical conditions are listed?
        3. Do you see 'Malaria' or 'Anaemia' being typed or selected?
        
        Respond JSON: {"clinical_view_visible": bool, "diagnosis_entry_visible": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('clinical_view_visible') or parsed.get('diagnosis_entry_visible'):
                vlm_score = vlm_points
                feedback.append("VLM verified clinical workflow.")
            else:
                feedback.append("VLM could not confirm clinical workflow visually.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If programmatic check passed perfectly, we can default VLM points or ignore
            if score >= 90: 
                vlm_score = vlm_points

    score += vlm_score

    # Final tally
    passed = (targets["Malaria"]["found"] and targets["Anaemia"]["found"])
    
    # Fallback: if they got everything right programmatically, ensure score is 100
    if passed and score < 100:
        score = 100
    
    final_feedback = " | ".join(feedback)
    if not feedback:
        final_feedback = f"No new diagnoses found matching criteria. Found: {found_diagnoses_names}"

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": final_feedback
    }