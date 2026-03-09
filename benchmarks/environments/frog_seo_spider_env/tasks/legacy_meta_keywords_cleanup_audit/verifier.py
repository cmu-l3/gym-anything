#!/usr/bin/env python3
"""
Verifier for Legacy Meta Keywords Cleanup Audit.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_meta_keywords_cleanup_audit(traj, env_info, task_info):
    """
    Verify that the agent configured Custom Search to find meta keywords in HTML Source.
    
    CRITICAL CHECK:
    - If the agent searches 'Page Text' (default), they will find 0 results.
    - If the agent searches 'HTML' (Source), they will find results on crawler-test.com.
    - Therefore, 'hit_count > 0' confirms they changed the configuration correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result
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
    
    # 1. App Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("App running (10/10)")
    else:
        feedback_parts.append("App not running (0/10)")

    # 2. File Created Correctly (30 pts)
    # Must exist AND be created during task AND contain target domain
    file_ok = (result.get('file_exists', False) and 
               result.get('file_created_during_task', False))
    
    if file_ok:
        score += 20
        feedback_parts.append("Export file created (20/20)")
        if result.get('valid_domain', False):
            score += 10
            feedback_parts.append("Target domain confirmed (10/10)")
        else:
            feedback_parts.append("Wrong domain in export (0/10)")
    else:
        feedback_parts.append("Export file missing or old (0/30)")

    # 3. Success Criteria: Hits Found (60 pts)
    # This is the proof that they switched to 'HTML' scope.
    hits = result.get('hit_count', 0)
    has_hits = result.get('has_hits', False)
    
    if has_hits and hits > 0:
        score += 60
        feedback_parts.append(f"Success: Found {hits} pages with meta keywords (Confirmed 'HTML' scope) (60/60)")
    else:
        if file_ok:
            feedback_parts.append("Failed: 0 hits found. Did you forget to change search scope to 'HTML' or 'Source'? Meta tags are not in 'Page Text'. (0/60)")
        else:
            feedback_parts.append("No hits checked (file missing) (0/60)")

    # Final Calculation
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }