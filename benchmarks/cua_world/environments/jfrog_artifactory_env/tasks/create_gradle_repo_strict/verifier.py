#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_gradle_repo_strict(traj, env_info, task_info):
    """
    Verifies that the gradle-libs-local repository was created with strict checksum policy.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check 1: Repository Existence (30 pts)
    if not result.get('repo_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Repository 'gradle-libs-local' was not created."
        }
    
    score = 30
    feedback = ["Repository 'gradle-libs-local' exists."]

    # Check 2: Package Type (30 pts)
    # Gradle repos typically have type='gradle' OR use 'gradle-default' layout with 'maven' type
    pkg_type = result.get('package_type', '')
    repo_layout = result.get('repo_layout', '')
    
    is_gradle = False
    if pkg_type and 'gradle' in pkg_type.lower():
        is_gradle = True
    elif repo_layout and 'gradle' in repo_layout.lower():
        is_gradle = True
        
    if is_gradle:
        score += 30
        feedback.append("Package type is Gradle.")
    else:
        feedback.append(f"Incorrect package type/layout. Type: {pkg_type}, Layout: {repo_layout}.")

    # Check 3: Checksum Policy (40 pts)
    # Expected: 'client-checksums' (Verify against client)
    policy = result.get('checksum_policy', '')
    if policy == 'client-checksums':
        score += 40
        feedback.append("Checksum policy is strictly set to 'Verify against client'.")
    else:
        feedback.append(f"Incorrect checksum policy: '{policy}' (Expected 'Verify against client').")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }