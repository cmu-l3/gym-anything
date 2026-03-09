#!/usr/bin/env python3
"""
Verifier for add_concept_synonym task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_concept_synonym(traj, env_info, task_info):
    """
    Verify that the synonym 'SBP' was added to the concept.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_synonym = metadata.get('target_synonym', 'SBP')
    
    # Retrieve result file
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
    feedback_parts = []
    
    # Check 1: API Data Availability (10 pts)
    concept_data = result.get('concept_data', {})
    if not concept_data or 'uuid' not in concept_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve concept data from OpenMRS API."
        }
    score += 10

    # Check 2: Synonym Presence (90 pts)
    names = concept_data.get('names', [])
    synonym_found = False
    synonym_obj = None

    for name_entry in names:
        # Check name text (exact match)
        if name_entry.get('name') == target_synonym:
            # Check if it's voided
            if not name_entry.get('voided'):
                synonym_found = True
                synonym_obj = name_entry
                break
    
    if synonym_found:
        score += 90
        feedback_parts.append(f"Success: Synonym '{target_synonym}' found in concept dictionary.")
    else:
        feedback_parts.append(f"Failure: Synonym '{target_synonym}' NOT found or is voided.")

    # Optional: Check if it's strictly a synonym vs fully specified name
    # In OpenMRS REST, 'conceptNameType' might be 'FULLY_SPECIFIED', 'SHORT', or null/INDEX_TERM for synonyms
    if synonym_found and synonym_obj:
        name_type = synonym_obj.get('conceptNameType')
        if name_type == 'FULLY_SPECIFIED':
             feedback_parts.append("Warning: Added as Fully Specified Name instead of Synonym (acceptable but not ideal).")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }