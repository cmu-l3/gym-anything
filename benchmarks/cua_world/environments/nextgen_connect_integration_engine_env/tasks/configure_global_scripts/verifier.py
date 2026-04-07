#!/usr/bin/env python3
"""
Verifier for configure_global_scripts task.

Verifies:
1. Scripts were actually modified via API.
2. Deploy script contains initialization logic.
3. Undeploy script contains finalization logic.
4. Preprocessor script contains tagging and timestamp logic.
5. Postprocessor script contains counting logic.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_global_scripts(traj, env_info, task_info):
    """
    Verify that global scripts are configured correctly for auditing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract data
    scripts_modified = result.get('scripts_modified', False)
    scripts = result.get('scripts_content', {})
    
    deploy_code = scripts.get('Deploy', '')
    undeploy_code = scripts.get('Undeploy', '')
    preproc_code = scripts.get('Preprocessor', '')
    postproc_code = scripts.get('Postprocessor', '')

    score = 0
    max_score = 100
    feedback_parts = []

    # CRITERION 1: Scripts modified (10 pts)
    if scripts_modified:
        score += 10
        feedback_parts.append("Scripts were modified from default.")
    else:
        feedback_parts.append("Scripts are unchanged from default state.")
        return {"passed": False, "score": 0, "feedback": "Scripts were not modified."}

    # CRITERION 2: Deploy Script (20 pts)
    # Needs: systemStartTime, auditMessageCount, log
    deploy_score = 0
    if 'globalMap.put' in deploy_code and 'systemStartTime' in deploy_code:
        deploy_score += 10
    if 'auditMessageCount' in deploy_code:
        deploy_score += 5
    if 'logger.info' in deploy_code and 'AUDIT_DEPLOY' in deploy_code:
        deploy_score += 5
    
    score += deploy_score
    feedback_parts.append(f"Deploy Script: {deploy_score}/20 pts")

    # CRITERION 3: Undeploy Script (10 pts)
    # Needs: logging
    undeploy_score = 0
    if 'logger.info' in undeploy_code and 'AUDIT_UNDEPLOY' in undeploy_code:
        undeploy_score += 10
    
    score += undeploy_score
    feedback_parts.append(f"Undeploy Script: {undeploy_score}/10 pts")

    # CRITERION 4: Preprocessor Script (30 pts)
    # Needs: auditReceivedTimestamp, auditTraceId (UUID), return message
    pre_score = 0
    if 'channelMap.put' in preproc_code and 'auditReceivedTimestamp' in preproc_code:
        pre_score += 10
    if 'auditTraceId' in preproc_code and ('UUID' in preproc_code or 'randomUUID' in preproc_code):
        pre_score += 10
    if 'return message' in preproc_code:
        pre_score += 5
    if 'logger.info' in preproc_code and 'AUDIT_PREPROCESSOR' in preproc_code:
        pre_score += 5

    score += pre_score
    feedback_parts.append(f"Preprocessor Script: {pre_score}/30 pts")

    # CRITERION 5: Postprocessor Script (30 pts)
    # Needs: increment auditMessageCount, log
    post_score = 0
    if 'globalMap.get' in postproc_code and 'auditMessageCount' in postproc_code:
        post_score += 10
    if 'globalMap.put' in postproc_code and 'auditMessageCount' in postproc_code:
        # Check for increment logic vaguely (presence of + or increment)
        if '+' in postproc_code or 'plus' in postproc_code or 'inc' in postproc_code:
             post_score += 10
        else:
             post_score += 5 # Half points if put/get exists but logic unclear
    if 'logger.info' in postproc_code and 'AUDIT_POSTPROCESSOR' in postproc_code:
        post_score += 10
    
    score += post_score
    feedback_parts.append(f"Postprocessor Script: {post_score}/30 pts")

    # Final tally
    passed = score >= 70
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }