#!/usr/bin/env python3
"""
Verifier for create_relationship_type task.

Checks:
1. A relationship type with 'aIsToB' = 'Community Health Worker' exists.
2. That same type has 'bIsToA' = 'Client'.
3. The description matches the requirement.
4. The type is not retired.
5. The type was created during the task (based on count increase or UUID check).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_relationship_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_a_to_b = metadata.get('expected_a_to_b', 'Community Health Worker').lower()
    expected_b_to_a = metadata.get('expected_b_to_a', 'Client').lower()
    required_keywords = metadata.get('required_description_keywords', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    relationship_types = result.get('relationship_types', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    score = 0
    feedback_parts = []
    
    # Find the target relationship type
    target_type = None
    for rt in relationship_types:
        # Check aIsToB
        a_name = rt.get('aIsToB', '').lower()
        if expected_a_to_b in a_name:
            target_type = rt
            break
            
    # CRITERION 1: Relationship Type Exists (30 pts)
    if target_type:
        score += 30
        feedback_parts.append(f"Relationship type '{target_type.get('aIsToB')}' found")
    else:
        feedback_parts.append(f"Relationship type '{expected_a_to_b}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Correct B-to-A Label (25 pts)
    b_name = target_type.get('bIsToA', '').lower()
    if expected_b_to_a in b_name:
        score += 25
        feedback_parts.append(f"Correct B-to-A label: {target_type.get('bIsToA')}")
    else:
        feedback_parts.append(f"Incorrect B-to-A label: found '{b_name}', expected '{expected_b_to_a}'")

    # CRITERION 3: Description Check (25 pts)
    # 15 pts for existence, 10 for content
    desc = target_type.get('description', '')
    if desc and len(desc) > 10:
        score += 15
        
        # Check keywords
        desc_lower = desc.lower()
        keywords_found = [k for k in required_keywords if k.lower() in desc_lower]
        if len(keywords_found) >= 2:
            score += 10
            feedback_parts.append("Description accurate")
        else:
            feedback_parts.append("Description too generic or missing keywords")
    else:
        feedback_parts.append("Description missing or too short")

    # CRITERION 4: Active Status (10 pts)
    if not target_type.get('retired', False):
        score += 10
        feedback_parts.append("Relationship type is active")
    else:
        feedback_parts.append("Relationship type is retired (inactive)")

    # CRITERION 5: Anti-gaming / Count check (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New record confirmed")
    else:
        # If we found the type but count didn't increase, it might have been pre-existing
        # (though setup cleans it) or agent modified another one.
        feedback_parts.append("Count did not increase (modified existing?)")

    passed = score >= 55  # Requires at least existence + correct names
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }