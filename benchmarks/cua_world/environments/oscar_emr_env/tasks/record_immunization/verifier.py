#!/usr/bin/env python3
"""
Verifier for Record Immunization Task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_immunization(traj, env_info, task_info):
    """
    Verify that the agent correctly recorded the two immunizations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result data
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

    records = result.get('immunization_records', [])
    task_start = result.get('task_start_timestamp', 0)
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    vaccine_targets = metadata.get('vaccines', [])
    
    score = 0
    max_score = 100
    feedback = []
    
    # Track found vaccines to avoid double counting
    found_vaccines = {v['type']: False for v in vaccine_targets}

    # Helper to check if string contains any keyword
    def matches_any(text, keywords):
        text = text.lower() if text else ""
        return any(k.lower() in text for k in keywords)

    # 2. Evaluate Records
    if not records:
        return {"passed": False, "score": 0, "feedback": "No immunization records found for patient."}

    for target in vaccine_targets:
        target_type = target['type']
        target_lot = target['lot']
        target_route = target['route']
        
        # Look for a matching record
        match_found = False
        best_record_score = 0
        best_record_feedback = []

        for record in records:
            # Check name match
            rec_name = record.get('name', '')
            if not matches_any(rec_name, target['keywords']):
                continue
            
            # We have a name match candidate
            current_score = 0
            current_feedback = []
            
            # 1. Base points for creating record (20 pts)
            current_score += 20
            current_feedback.append(f"Created {target_type} record")
            
            # 2. Check Lot Number (10 pts)
            rec_lot = record.get('lot', '')
            if target_lot.lower() in rec_lot.lower():
                current_score += 10
            else:
                current_feedback.append(f"Wrong Lot (expected {target_lot}, got '{rec_lot}')")
                
            # 3. Check Site (10 pts)
            rec_site = record.get('site', '')
            if matches_any(rec_site, target['site_keywords']):
                current_score += 10
            else:
                current_feedback.append(f"Wrong Site (got '{rec_site}')")

            # 4. Check Route (10 pts)
            rec_route = record.get('route', '')
            if target_route.lower() in rec_route.lower():
                current_score += 10
            else:
                current_feedback.append(f"Wrong Route (expected {target_route}, got '{rec_route}')")

            # Update best match for this target
            if current_score > best_record_score:
                best_record_score = current_score
                best_record_feedback = current_feedback
                match_found = True

        if match_found:
            score += best_record_score
            found_vaccines[target_type] = True
            feedback.extend(best_record_feedback)
        else:
            feedback.append(f"Missing record for {target_type}")

    # 3. Anti-gaming / System checks (optional extra points or validation)
    # We integrated the "Record Created" points (20) into the loop above.
    # Total possible so far: 2 vaccines * 50 pts = 100 pts.
    
    passed = (score >= 70) and all(found_vaccines.values())

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }