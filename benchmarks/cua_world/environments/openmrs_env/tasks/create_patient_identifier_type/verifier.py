#!/usr/bin/env python3
"""
Verifier for create_patient_identifier_type task.
Checks if the metadata entity was created with correct constraints.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_identifier_type(traj, env_info, task_info):
    """
    Verify creation of Patient Identifier Type 'National ART Number'.
    
    Criteria:
    1. Entity exists (30 pts)
    2. Name matches exactly (20 pts)
    3. Constraints correct (Unique, Not Required) (20 pts)
    4. Lengths correct (Min 4, Max 15) (15 pts)
    5. Description matches (15 pts)
    6. Anti-gaming: Created after task start
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "National ART Number")
    
    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Existence (30 pts)
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Identifier Type 'National ART Number' not found in system."
        }
    
    data = result.get('data', {})
    score += 30
    feedback_parts.append("Identifier Type created")

    # 2. Check Name (20 pts)
    # The API query was by name, but we double check exact string match
    name = data.get('name', '')
    if name == expected_name:
        score += 20
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name mismatch ('{name}')")

    # 3. Check Constraints (20 pts)
    # Required should be False
    req = data.get('required')
    # Uniqueness should be 'UNIQUE' (OpenMRS REST API usually returns string enum)
    uniq = data.get('uniquenessBehavior')
    
    constraints_ok = True
    if req is not False:
        constraints_ok = False
        feedback_parts.append(f"Incorrect 'Required' setting ({req})")
    
    if uniq != "UNIQUE":
        constraints_ok = False
        feedback_parts.append(f"Incorrect Uniqueness ({uniq})")
        
    if constraints_ok:
        score += 20
        feedback_parts.append("Constraints (Unique/Required) correct")
        
    # 4. Check Lengths (15 pts)
    min_len = data.get('minLength')
    max_len = data.get('maxLength')
    
    lengths_ok = True
    if min_len != metadata.get('expected_min_length', 4):
        lengths_ok = False
        feedback_parts.append(f"Min length wrong ({min_len})")
    
    if max_len != metadata.get('expected_max_length', 15):
        lengths_ok = False
        feedback_parts.append(f"Max length wrong ({max_len})")
        
    if lengths_ok:
        score += 15
        feedback_parts.append("Length constraints correct")

    # 5. Check Description (15 pts)
    desc = data.get('description', '')
    expected_desc = metadata.get('expected_description', '')
    if expected_desc.lower() in desc.lower():
        score += 15
        feedback_parts.append("Description correct")
    else:
        feedback_parts.append("Description mismatch")

    # Anti-gaming: Timestamp check
    # We parse the ISO string from OpenMRS
    date_created_str = data.get('dateCreated')
    task_start_ts = result.get('task_start_ts', 0)
    
    timestamp_valid = False
    if date_created_str:
        try:
            # OpenMRS format example: "2023-10-25T12:00:00.000+0000"
            # Simplified parsing ignoring timezone for rough check or use strptime
            # Python 3.7+ supports fromisoformat if format is standard, but OpenMRS often sends +0000 which needs adjustment
            dt_str = date_created_str.replace("+0000", "+00:00")
            created_ts = datetime.fromisoformat(dt_str).timestamp()
            
            # Allow small buffer for clock skew
            if created_ts > (task_start_ts - 5):
                timestamp_valid = True
            else:
                feedback_parts.append("Item existed before task started")
        except Exception:
            # Fallback if parsing fails - assume valid if found newly
            logger.warning(f"Could not parse timestamp {date_created_str}, skipping strict time check")
            timestamp_valid = True
    
    if not timestamp_valid:
        score = 0
        feedback_parts = ["Anti-gaming check failed: Item pre-dated task"]

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }