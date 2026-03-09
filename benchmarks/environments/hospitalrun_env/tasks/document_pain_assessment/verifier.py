#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_pain_assessment(traj, env_info, task_info):
    """
    Verifies that the 'Pain Assessment' form was correctly filled out for Lars Jensen.
    """
    # 1. Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    metadata = task_info.get("metadata", {})
    expected_values = metadata.get("expected_values", {})
    patient_id = metadata.get("couch_patient_id", "patient_p1_000100")

    # 2. Retrieve Data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_dump = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    
    try:
        # Get result metadata
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            result_meta = json.load(f)

        # Get CouchDB dump
        copy_from_env("/tmp/couch_dump.json", temp_dump.name)
        with open(temp_dump.name) as f:
            couch_data = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_dump.name): os.unlink(temp_dump.name)

    # 3. Analyze Data
    # Search for a document containing the form data linked to the patient
    rows = couch_data.get("rows", [])
    found_doc = None
    
    for row in rows:
        doc = row.get("doc", {})
        data = doc.get("data", doc) # Handle nested data wrapper
        
        # Check linkage to patient (directly or via visit)
        # Note: Custom form data might be embedded in the visit document or separate.
        # We check for the specific keys we asked the agent to input.
        
        # Check if this doc belongs to Lars Jensen
        is_linked = False
        if data.get("patient") == patient_id: is_linked = True
        if "Lars" in str(data) and "Jensen" in str(data): is_linked = True # Fallback loose check
        
        if not is_linked:
            continue
            
        # Check for form fields
        # The agent was asked to enter: Pain Score: 6, Location: Lower Back
        pain_score = str(data.get("painScore", ""))
        location = str(data.get("location", ""))
        
        if "6" in pain_score or "Lower Back" in location:
            found_doc = data
            break

    # 4. Score
    score = 0
    feedback = []
    
    if found_doc:
        score += 40
        feedback.append("Found Pain Assessment data linked to patient.")
        
        # Verify specific fields
        # Pain Score (10 pts)
        actual_score = str(found_doc.get("painScore", ""))
        if expected_values["painScore"] == actual_score:
            score += 10
            feedback.append("Pain Score correct (6).")
        else:
            feedback.append(f"Pain Score mismatch: expected 6, got '{actual_score}'")

        # Location (10 pts)
        actual_loc = str(found_doc.get("location", ""))
        if expected_values["location"].lower() in actual_loc.lower():
            score += 10
            feedback.append("Location correct.")
        else:
            feedback.append(f"Location mismatch: expected '{expected_values['location']}', got '{actual_loc}'")
            
        # Duration (10 pts)
        actual_dur = str(found_doc.get("duration", ""))
        if expected_values["duration"].lower() in actual_dur.lower():
            score += 10
            feedback.append("Duration correct.")
        else:
            feedback.append(f"Duration mismatch: expected '{expected_values['duration']}', got '{actual_dur}'")

        # Aggravating Factors (10 pts)
        actual_agg = str(found_doc.get("aggravatingFactors", ""))
        if "bending" in actual_agg.lower() or "lifting" in actual_agg.lower():
            score += 10
            feedback.append("Aggravating factors correct.")
        else:
            feedback.append(f"Aggravating factors mismatch.")
            
        # Anti-gaming: Check timestamp/rev (Implicitly handled by verifying new data exists vs seed)
        # The seed did NOT contain these fields, so existence implies creation.
        score += 20 # Bonus for data integrity/existence
        
    else:
        feedback.append("No document found containing the specific Pain Assessment data linked to Lars Jensen.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }