#!/usr/bin/env python3
"""
Verifier for resolve_incident_report task.

Checks:
1. Target incident (incident_p1_000001) status is 'Resolved'.
2. Target incident description contains resolution notes.
3. No duplicate incidents were created.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_incident_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_id = metadata.get('target_incident_id', 'incident_p1_000001')
    expected_statuses = [s.lower() for s in metadata.get('expected_status', ['Resolved', 'Closed'])]
    required_keywords = metadata.get('required_resolution_keywords', ['replaced', 'wheel'])

    # Load result
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
    feedback = []
    
    # Check 1: Validate Target Document Existence
    target_doc = result.get('target_doc', {})
    if not target_doc or target_doc.get('_id') != target_id:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target incident record was deleted or could not be found."
        }
    
    data = target_doc.get('data', {})
    
    # Check 2: Status Update (40 pts)
    # Status can be in 'status' field
    status = data.get('status', '').lower()
    
    if status in expected_statuses:
        score += 40
        feedback.append("Status correctly updated to Resolved.")
    else:
        feedback.append(f"Status is '{status}', expected 'Resolved'.")

    # Check 3: Resolution Note Content (40 pts)
    # The user might append to description or use a dedicated outcome field if it exists
    # We check the description field primarily as that's the main text area in HRv1 incidents
    description = data.get('description', '').lower()
    outcome = data.get('outcome', '').lower() # Some schemas might use this
    full_text = f"{description} {outcome}"
    
    missing_keywords = [kw for kw in required_keywords if kw.lower() not in full_text]
    
    if not missing_keywords:
        score += 40
        feedback.append("Resolution details recorded correctly.")
    else:
        # Partial credit if they updated status but forgot note?
        feedback.append(f"Missing keywords in documentation: {', '.join(missing_keywords)}.")

    # Check 4: Anti-Gaming / Correct Record (20 pts)
    # Verify they didn't just create a NEW incident instead of editing the old one
    all_incidents = result.get('all_incidents', [])
    
    # Filter for incidents that look like the target
    potential_dupes = 0
    for inc in all_incidents:
        inc_data = inc.get('data', {})
        inc_desc = inc_data.get('description', '').lower()
        if 'broken wheelchair' in inc_desc and inc.get('id') != target_id:
            potential_dupes += 1
            
    if potential_dupes > 0:
        feedback.append("Warning: New incident created instead of editing existing one.")
        score = max(0, score - 20) # Penalize for creating duplicate
    else:
        score += 20
        feedback.append("Correctly edited existing record.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }