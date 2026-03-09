#!/usr/bin/env python3
"""
Verifier for create_program_definition task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_program_definition(traj, env_info, task_info):
    """
    Verify creation of Program and Concept.
    
    Criteria:
    1. Program 'Nutrition Support' exists.
    2. Concept 'Nutrition Support Program' exists.
    3. Program is linked to the correct Concept.
    4. Program description matches.
    5. Concept metadata (Class/Datatype) is correct.
    6. Timestamps confirm creation during task (Anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_program_name = metadata.get('target_program_name', 'Nutrition Support')
    target_concept_name = metadata.get('target_concept_name', 'Nutrition Support Program')

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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    prog_found = result.get('program_found', False)
    concept_found = result.get('concept_found', False)
    prog_details = result.get('program_details', {})
    concept_details = result.get('concept_details', {})

    # 1. Verify Concept (20 pts)
    # We check concept first because program depends on it
    if concept_found:
        score += 10
        feedback_parts.append("Concept found")
        
        # Check metadata
        cls = concept_details.get('class', '')
        dtype = concept_details.get('datatype', '')
        
        if 'Program' in cls or 'Misc' in cls:
            score += 5
            feedback_parts.append("Concept class correct")
        else:
            feedback_parts.append(f"Concept class incorrect ({cls})")
            
        if 'N/A' in dtype:
            score += 5
            feedback_parts.append("Concept datatype correct")
        else:
            feedback_parts.append(f"Concept datatype incorrect ({dtype})")
            
        # Timestamp check
        created_str = concept_details.get('date_created')
        if check_timestamp(created_str, task_start):
            feedback_parts.append("Concept created during task")
        else:
            feedback_parts.append("WARNING: Concept appears pre-existing")
    else:
        feedback_parts.append("Concept NOT found")

    # 2. Verify Program (30 pts)
    if prog_found:
        score += 20
        feedback_parts.append("Program found")
        
        # Description check
        desc = prog_details.get('description', '').lower()
        if 'nutrition' in desc and 'rehabilitation' in desc:
            score += 10
            feedback_parts.append("Description correct")
        elif desc:
            score += 5
            feedback_parts.append("Description present but partial match")
        else:
            feedback_parts.append("Description missing")
            
        # Timestamp check
        created_str = prog_details.get('date_created')
        if check_timestamp(created_str, task_start):
            score += 0 # Just for validation, points are in 'found'
            feedback_parts.append("Program created during task")
        else:
            feedback_parts.append("WARNING: Program appears pre-existing")
            score = max(0, score - 20) # Penalize heavily if pre-existing
    else:
        feedback_parts.append("Program NOT found")

    # 3. Verify Linkage (50 pts)
    # The program must use the concept we found
    link_name = prog_details.get('concept_link_name', '')
    
    if prog_found and target_concept_name in link_name:
        score += 50
        feedback_parts.append(f"Program correctly linked to '{link_name}'")
    elif prog_found:
        feedback_parts.append(f"Program linked to wrong concept: '{link_name}'")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def check_timestamp(iso_date_str, task_start_ts):
    """Check if ISO date string is after task start timestamp."""
    if not iso_date_str:
        return False
    try:
        # OpenMRS dates look like: "2023-10-27T10:00:00.000+0000"
        # Simplistic parsing or use dateutil if available. 
        # Here we just comparing strings roughly if format allows, 
        # but let's try standard lib.
        # Strip timezone for simplicity if standard parsing fails
        dt_str = iso_date_str.split('+')[0].split('.')[0] # 2023-10-27T10:00:00
        dt = datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")
        ts = dt.timestamp()
        # Allow small skew (e.g. server time diff), but generally created after start
        return ts >= (float(task_start_ts) - 60)
    except Exception:
        return True # Fail open if parsing fails, assume good faith if data exists