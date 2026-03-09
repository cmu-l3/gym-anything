#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_cab(traj, env_info, task_info):
    """
    Verify that the Technical Infrastructure CAB was created with correct members.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_cab_name', "Technical Infrastructure CAB")
    expected_members = set(metadata.get('expected_members', ["David Chen", "Sarah Miller"]))
    expected_desc_keywords = metadata.get('expected_description_keywords', [])

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. CAB Existence (40 pts)
    if result.get("cab_exists"):
        score += 40
        feedback.append("CAB created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "CAB 'Technical Infrastructure CAB' was not found."}

    # 2. Anti-Gaming Check (10 pts)
    # Ensure it was created during the task
    if result.get("created_during_task"):
        score += 10
    else:
        feedback.append("Warning: CAB count did not increase (possibly pre-existing or deleted/recreated).")

    # 3. Member Verification (30 pts)
    # Check if expected members are present
    actual_members = result.get("members", [])
    # Normalize names (strip whitespace, lowercase comparison if needed)
    actual_members_clean = {m.strip() for m in actual_members}
    
    found_members = 0
    for member in expected_members:
        # Simple containment check
        if any(member.lower() in am.lower() for am in actual_members_clean):
            found_members += 1
        else:
            feedback.append(f"Missing member: {member}")
            
    if found_members == len(expected_members):
        score += 30
        feedback.append("All required members added.")
    elif found_members > 0:
        score += 15
        feedback.append(f"Only {found_members}/{len(expected_members)} members found.")
    else:
        feedback.append("No correct members found.")

    # 4. Description Verification (20 pts)
    description = result.get("cab_description", "").lower()
    keywords_found = 0
    for kw in expected_desc_keywords:
        if kw.lower() in description:
            keywords_found += 1
            
    if keywords_found >= len(expected_desc_keywords):
        score += 20
        feedback.append("Description is correct.")
    elif keywords_found > 0:
        score += 10
        feedback.append("Description partially correct.")
    else:
        feedback.append("Description missing key terms.")

    # Final tally
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }