#!/usr/bin/env python3
"""
Verifier for Restore Job from Backup task.

Verifies that:
1. The job 'Production-Deploy-Pipeline' exists.
2. It is a Pipeline job.
3. It has the correct configuration (Parameters, Script, Triggers, LogRotator).
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_job_from_backup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/restore_job_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Job Existence (Critical) - 20 pts
    if result.get('job_exists', False):
        score += 20
        feedback_parts.append("Job 'Production-Deploy-Pipeline' restored.")
    else:
        return {"passed": False, "score": 0, "feedback": "Job 'Production-Deploy-Pipeline' was NOT found in Jenkins."}

    # 2. Job Type - 10 pts
    job_class = result.get('job_class', '')
    if 'WorkflowJob' in job_class:
        score += 10
        feedback_parts.append("Job type is correct (Pipeline).")
    else:
        feedback_parts.append(f"Incorrect job type: {job_class}")

    # 3. Configuration Verification
    config = result.get('config_verification', {})
    
    # Pipeline Script (20 pts)
    if config.get('has_pipeline_script', False):
        score += 20
        feedback_parts.append("Pipeline script content verification passed.")
    else:
        feedback_parts.append("Pipeline script does not match backup (missing repo URL).")

    # Parameters (20 pts)
    if config.get('has_param_deploy', False) and config.get('has_param_build', False):
        score += 20
        feedback_parts.append("Job parameters (DEPLOY_ENV, BUILD_TYPE) restored correctly.")
    elif config.get('has_param_deploy', False) or config.get('has_param_build', False):
        score += 10
        feedback_parts.append("Partial parameters restored.")
    else:
        feedback_parts.append("Job parameters missing.")

    # SCM Trigger (15 pts)
    if config.get('has_scm_trigger', False):
        score += 15
        feedback_parts.append("SCM Polling trigger restored.")
    else:
        feedback_parts.append("SCM Polling trigger missing or incorrect.")

    # Log Rotator (15 pts)
    if config.get('has_log_rotator', False):
        num_keep = str(config.get('log_rotator_num', '0'))
        if num_keep == '10':
            score += 15
            feedback_parts.append("Log rotation settings correct (Keep 10).")
        else:
            score += 5
            feedback_parts.append(f"Log rotation enabled but wrong value (Found: {num_keep}, Expected: 10).")
    else:
        feedback_parts.append("Log rotation setting missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }