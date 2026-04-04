#!/usr/bin/env python3
"""
Verifier for record_vineyard_maturity_sampling task.

Verifies:
1. An Observation log exists.
2. The log date corresponds to Sept 14, 2024.
3. The log contains specific quantities (Brix, pH, TA) with correct units.
4. The notes contain key phrases.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vineyard_maturity(traj, env_info, task_info):
    """
    Verify the vineyard maturity log creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_quantities = metadata.get('expected_quantities', [])
    expected_date_str = metadata.get('expected_date', "2024-09-14")
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            content = f.read()
            # Simple cleanup for potential concatenated outputs
            if "{" in content:
                content = content[content.find("{"):content.rfind("}")+1]
            result = json.loads(content)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from device. Agent may not have saved the log properly."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Results
    score = 0
    feedback_parts = []
    
    # Check if log exists
    if not result.get('log_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No observation log was found in the database."
        }
    
    score += 10
    feedback_parts.append("Log created successfully")

    # Check Timestamp (Date)
    # farmOS stores timestamps as seconds since epoch or ISO strings depending on version.
    # The setup script extraction might return raw SQLite data.
    # Assuming the app stores it as a standard timestamp format.
    # We will look for "2024-09-14" in the timestamp string.
    
    log_timestamp = str(result.get('timestamp', ''))
    # Convert epoch if necessary (if it looks like a large integer)
    if log_timestamp.isdigit() and len(log_timestamp) > 8:
        try:
            dt = datetime.fromtimestamp(int(log_timestamp) / 1000) # often ms in Java apps
            log_date = dt.strftime("%Y-%m-%d")
        except:
            log_date = log_timestamp
    else:
        log_date = log_timestamp

    if expected_date_str in log_date:
        score += 15
        feedback_parts.append("Correct date (Sept 14, 2024)")
    else:
        feedback_parts.append(f"Incorrect date: {log_date}")

    # Check Quantities
    # We need to match found quantities against expected ones
    found_quantities = result.get('quantities', [])
    matched_quantities = 0
    
    # Helper to clean strings
    def clean(s): return str(s).lower().strip() if s else ""

    for expected in expected_quantities:
        exp_val = clean(expected['value'])
        exp_unit = clean(expected['unit'])
        exp_label = clean(expected['label'])
        
        match_found = False
        for found in found_quantities:
            f_val = clean(found.get('value'))
            f_unit = clean(found.get('unit'))
            f_label = clean(found.get('label'))
            
            # Check value match (exact)
            val_match = (f_val == exp_val)
            
            # Check unit match (partial allowed, e.g. "brix" in "degrees brix")
            unit_match = (exp_unit in f_unit)
            
            # Check label match (partial allowed)
            label_match = (exp_label in f_label) if exp_label else True
            
            if val_match and unit_match:
                match_found = True
                break
        
        if match_found:
            matched_quantities += 1
            score += 20 # 60 points total for 3 quantities
            feedback_parts.append(f"Found {expected['value']} {expected['unit']}")
        else:
            feedback_parts.append(f"Missing {expected['value']} {expected['unit']}")

    # Check Notes
    notes = str(result.get('notes', ''))
    keywords = metadata.get('expected_notes_keywords', [])
    found_keywords = [k for k in keywords if k.lower() in notes.lower()]
    
    if len(found_keywords) >= 3:
        score += 15
        feedback_parts.append("Notes contain required details")
    elif len(found_keywords) > 0:
        score += 5
        feedback_parts.append("Notes partially correct")
    else:
        feedback_parts.append("Notes missing key details")

    # Final Verification
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }