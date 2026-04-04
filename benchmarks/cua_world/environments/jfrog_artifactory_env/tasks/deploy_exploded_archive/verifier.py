#!/usr/bin/env python3
"""
Verifier for deploy_exploded_archive task.
Verifies that the Javadoc JAR was deployed and EXPLODED (extracted) into the repository.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_exploded_archive(traj, env_info, task_info):
    """
    Verify deployment and explosion of the Javadoc archive.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # 1. API Accessibility (Pre-requisite)
    if not result.get('api_accessible', False):
        return {"passed": False, "score": 0, "feedback": "Artifactory API was not accessible at verification time."}

    # 2. Check for critical exploded file (index.html) - 60 points
    index_exists = result.get('index_html_exists', False)
    if index_exists:
        score += 60
        feedback_parts.append("Found exploded 'index.html' at correct path.")
    else:
        feedback_parts.append("Missing 'index.html' at 'javadocs/commons-lang3/'.")

    # 3. Check for secondary exploded file (element-list) - 20 points
    # This confirms it's likely a full extraction and not just a single uploaded file named index.html
    element_list_exists = result.get('element_list_exists', False)
    if element_list_exists:
        score += 20
        feedback_parts.append("Found exploded 'element-list'.")
    
    # 4. Check for correct path structure - 20 points
    # If index exists, the path is inherently correct based on the check URL in export_result.sh
    # But we also deduct if we detect common error states
    
    # Error State: JAR uploaded but not exploded
    jar_unexploded = result.get('jar_exists_unexploded', False)
    target_is_file = result.get('target_is_file_not_folder', False)
    
    if jar_unexploded or target_is_file:
        feedback_parts.append("ERROR: It appears the archive was uploaded as a file/JAR but NOT exploded.")
        # If they somehow got index.html but also left the jar, we verify collision? 
        # Usually explode keeps the jar or removes it depending on settings, but missing index.html is the key failure.
    
    # 5. Anti-gaming: Creation time check
    creation_valid = result.get('creation_time_valid', False)
    if index_exists and not creation_valid:
        feedback_parts.append("WARNING: File timestamps indicate pre-existing data (anti-gaming check failed).")
        score = 0 # Fail if data wasn't created during task

    if index_exists:
        score += 20 # Bonus for getting the path perfectly right (implied by index_exists)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }