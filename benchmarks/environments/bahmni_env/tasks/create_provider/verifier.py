#!/usr/bin/env python3
"""
Verifier for create_provider task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_provider(traj, env_info, task_info):
    """
    Verify that the healthcare provider was correctly created in OpenMRS.
    
    Scoring Criteria:
    1. Provider Record Exists (30 pts)
    2. Identifier Matches Exactly (25 pts)
    3. Name Matches (Kenji Tanaka) (20 pts)
    4. Provider is Active (Not Retired) (10 pts)
    5. Anti-Gaming: Created during task / Count increased (15 pts)
    
    Pass Threshold: 75/100 (Must at least exist with correct details)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    target_identifier = metadata.get('target_identifier', 'DOC-2024-0047')
    required_name_parts = metadata.get('required_parts', ['Kenji', 'Tanaka'])

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    provider_found = result.get("provider_found", False)
    provider_data = result.get("provider_data", {})
    
    # CRITERION 1: Provider Exists (30 pts)
    if provider_found:
        score += 30
        feedback_parts.append("Provider record found")
    else:
        feedback_parts.append("Provider record NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Identifier Check (25 pts)
    actual_id = provider_data.get("identifier", "")
    if actual_id == target_identifier:
        score += 25
        feedback_parts.append(f"Identifier correct ({actual_id})")
    else:
        feedback_parts.append(f"Identifier incorrect (Expected: {target_identifier}, Found: {actual_id})")

    # CRITERION 3: Name Check (20 pts)
    # Check both 'name' (direct) and 'person_name' (linked person) fields
    actual_name = (provider_data.get("name") or "") + " " + (provider_data.get("person_name") or "")
    name_matches = all(part.lower() in actual_name.lower() for part in required_name_parts)
    
    if name_matches:
        score += 20
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name incorrect (Found: {actual_name})")

    # CRITERION 4: Active Status (10 pts)
    is_active = result.get("is_active", False)
    if is_active:
        score += 10
        feedback_parts.append("Provider is active")
    else:
        feedback_parts.append("Provider is retired (inactive)")

    # CRITERION 5: Anti-Gaming / Freshness (15 pts)
    # The setup script specifically deleted this ID, so existence implies creation.
    # We also check the created_during_task flag derived from logic in export_result.sh
    created_fresh = result.get("created_during_task", False)
    count_increased = result.get("current_count", 0) > result.get("initial_count", 0)
    
    if created_fresh or count_increased:
        score += 15
        feedback_parts.append("Record created during task")
    else:
        feedback_parts.append("Warning: Could not verify record was created in this session")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }