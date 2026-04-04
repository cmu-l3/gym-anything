#!/usr/bin/env python3
"""
Verifier for configure_virtual_deploy_target task.

Verifies that the virtual repository 'libs-virtual' has been configured
with 'example-repo-local' as its defaultDeploymentRepo.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_virtual_deploy_target(traj, env_info, task_info):
    """
    Verify the repository configuration.
    """
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Get expected values
    metadata = task_info.get('metadata', {})
    expected_virtual = metadata.get('virtual_repo', 'libs-virtual')
    expected_target = metadata.get('target_deploy_repo', 'example-repo-local')

    # 3. Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found. Did the task setup/export fail?"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Task result file is corrupted."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Verify API accessibility
    if result.get('api_status') != 'accessible':
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Artifactory API was unreachable during verification. Ensure Artifactory is running."
        }

    # 5. Check configuration
    repo_config = result.get('repo_config', {})
    
    # Check if we got the right repo
    actual_key = repo_config.get('key')
    if actual_key != expected_virtual:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve configuration for {expected_virtual}. Got: {actual_key}"
        }

    # Check the specific setting
    actual_target = repo_config.get('defaultDeploymentRepo')
    
    # Debug info
    logger.info(f"Repo: {actual_key}, DefaultDeploy: {actual_target}, Expected: {expected_target}")

    if actual_target == expected_target:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Success: '{expected_virtual}' is correctly configured to deploy to '{expected_target}'."
        }
    elif not actual_target:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed: 'Default Deployment Repository' is not set for '{expected_virtual}'."
        }
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed: Incorrect deployment target. Expected '{expected_target}', but got '{actual_target}'."
        }