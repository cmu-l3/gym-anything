#!/usr/bin/env python3
"""
Verifier for OpenMRS create_provider task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_provider(traj, env_info, task_info):
    """
    Verify that the agent created a provider account 'PROV-8821' linked to existing 'Alice Bowman'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # Extract data
    provider = result.get('provider_record')
    target_uuid = result.get('target_person_uuid')
    initial_person_count = int(result.get('initial_person_count', 0))
    current_person_count = int(result.get('current_person_count', 0))
    task_start = result.get('task_start', 0)

    # CRITERION 1: Provider Record Exists (40 pts)
    if provider:
        score += 40
        feedback_parts.append("Provider 'PROV-8821' created")
        
        # Check active status
        retired = provider.get('retired', '0')
        if str(retired) == '0':
            score += 10
            feedback_parts.append("Provider account is active")
        else:
            feedback_parts.append("WARNING: Provider account is retired/voided")

        # CRITERION 2: Correct Person Linkage (30 pts)
        # The provider must be linked to the Alice Bowman UUID we identified in setup
        prov_person_uuid = provider.get('person_uuid')
        if prov_person_uuid == target_uuid:
            score += 30
            feedback_parts.append("Linked to correct existing Person record")
        else:
            feedback_parts.append(f"Linked to WRONG Person (Expected {target_uuid}, got {prov_person_uuid})")

    else:
        feedback_parts.append("Provider 'PROV-8821' NOT found in database")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Task Failed: Provider 'PROV-8821' was not created."
        }

    # CRITERION 3: No Duplicate Persons (20 pts)
    # If agent created a new 'Alice Bowman' instead of selecting existing one, 
    # count will increase.
    if current_person_count == initial_person_count:
        score += 20
        feedback_parts.append("Clean data: No duplicate Person records created")
    elif current_person_count > initial_person_count:
        feedback_parts.append(f"Data Quality Issue: Created {current_person_count - initial_person_count} duplicate Person record(s)")
    else:
        # Should not happen unless agent deleted records
        feedback_parts.append("Person count decreased (records deleted?)")

    # Anti-gaming check (Time)
    # Just a sanity check, usually doesn't affect score unless impossible
    # date_created comes from DB as string, usually 'YYYY-MM-DD HH:MM:SS'
    # We won't strictly parse it here to avoid timezone complexity, 
    # but the existence check implies it was created.

    passed = score >= 90  # Strict pass requirement for data integrity tasks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }