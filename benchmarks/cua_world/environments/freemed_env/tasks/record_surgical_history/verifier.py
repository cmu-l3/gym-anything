#!/usr/bin/env python3
"""
Verifier for record_surgical_history task.

Evaluates the agent's performance by:
1. Programmatically checking the FreeMED MySQL database for a newly created clinical record containing "Cholecystectomy".
2. Confirming the record is linked to the target patient ID (Thomas Anderson).
3. Confirming ancillary clinical details (Date, Facility, Notes) were correctly inputted.
4. Using a Vision-Language Model (VLM) to verify trajectory workflow (chart navigation).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory frames from a user working in the FreeMED EMR system.
    
Did the user navigate to the Surgical History / Surgeries module for the patient Thomas Anderson?
Look for indications of:
1. Searching for or opening the chart for "Thomas Anderson".
2. Clicking on a module named "Surgical History", "Surgeries", or "Past Medical History".
3. Form fields being filled out with terms like "Cholecystectomy", "Mercy General", or "2018".

Respond in JSON format with exactly these keys:
{
    "patient_opened": true/false,
    "module_accessed": true/false,
    "data_entered": true/false,
    "observations": "brief explanation of what you see"
}"""


def verify_surgical_history(traj, env_info, task_info):
    # Retrieve the copy_from_env function required to access container files safely
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch configuration metadata
    metadata = task_info.get('metadata', {})
    expected_procedure = metadata.get('procedure', 'Cholecystectomy').lower()
    expected_facility = metadata.get('facility', 'Mercy General').lower()
    expected_date = '2018'

    score = 0
    feedback_parts = []
    
    # Copy and parse the JSON result from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. Primary Programmatic Verification
    db_success = result_data.get("success", False)
    records = result_data.get("records", [])
    
    if not db_success:
        return {"passed": False, "score": 0, "feedback": f"Database scan failed: {result_data.get('error')}"}
        
    if not records:
        feedback_parts.append("No clinical records containing 'Cholecystectomy' were found in the database.")
    else:
        # Find the best matching record
        best_record = None
        for r in records:
            if r.get("linked_to_patient"):
                best_record = r
                break
                
        if not best_record:
            # Found records, but linked to wrong patient
            score += 10
            feedback_parts.append("Procedure recorded, but NOT linked to Thomas Anderson's patient ID.")
            # Use the first one for partial text analysis
            best_record = records[0]
        else:
            score += 40
            feedback_parts.append("Procedure recorded and successfully linked to Thomas Anderson.")
            
        # Check text fields in the found record
        row_data = best_record.get("row_data", {})
        row_text_aggregate = " ".join([str(v).lower() for v in row_data.values()])
        
        # Check specific metadata constraints
        if expected_procedure.lower() in row_text_aggregate:
            score += 15
            feedback_parts.append("Procedure name correct.")
            
        if expected_facility.lower() in row_text_aggregate or "mercy" in row_text_aggregate:
            score += 15
            feedback_parts.append("Facility/Location correct.")
            
        if expected_date in row_text_aggregate:
            score += 10
            feedback_parts.append("Surgery date recorded correctly.")

    # 2. VLM Verification (Trajectory Analysis)
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    
    if query_vlm and len(traj) > 0:
        frames = sample_trajectory_frames(traj, n=5)
        try:
            vlm_response = query_vlm(prompt=build_vlm_prompt(), images=frames)
            vlm_parsed = vlm_response.get("parsed", {})
            
            if vlm_parsed.get("patient_opened") and vlm_parsed.get("module_accessed"):
                score += 10
                feedback_parts.append("VLM confirmed patient chart navigation.")
            
            if vlm_parsed.get("data_entered"):
                score += 10
                feedback_parts.append("VLM confirmed data entry interactions.")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped/failed.")

    # Determine final outcome
    # Strict pass conditions: Needs the DB record linked to patient AND at least one text criteria correct
    passed = score >= 65 and any(r.get("linked_to_patient") for r in records)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }