#!/usr/bin/env python3
"""Verifier for migrate_order_id_type task."""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_migrate_order_id_type(traj, env_info, task_info):
    """Verify that Order.id was refactored from int to long correctly.

    Criteria:
    1. Project compiles successfully (40 pts)
    2. Tests pass (30 pts)
    3. Order.java contains 'long id' (20 pts)
    4. OrderRepository.java uses 'findById(long)' (10 pts)
    
    Bonus: VLM verification of UI usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # 2. Check Build Status (40 pts)
    compile_code = result.get('compile_exit_code', -1)
    if compile_code == 0:
        score += 40
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed")
        if result.get('compile_log'):
            feedback_parts.append(f"Compile Error Snippet: {result['compile_log']}")

    # 3. Check Test Status (30 pts)
    test_code = result.get('test_exit_code', -1)
    if test_code == 0:
        score += 30
        feedback_parts.append("All tests passed")
    else:
        feedback_parts.append("Tests failed")

    # 4. Check Order.java Content (20 pts)
    order_content = result.get('order_java_content', '')
    if order_content:
        # Look for "private long id"
        has_long_field = bool(re.search(r'private\s+(long|Long)\s+id\s*;', order_content))
        # Look for "long getId()"
        has_long_getter = bool(re.search(r'public\s+(long|Long)\s+getId\s*\(', order_content))
        
        if has_long_field and has_long_getter:
            score += 20
            feedback_parts.append("Order.java: id field and getter converted to long")
        elif has_long_field:
            score += 10
            feedback_parts.append("Order.java: id field is long, but getter might be wrong")
        else:
            feedback_parts.append("Order.java: id field is NOT long")
    else:
        feedback_parts.append("Order.java content missing")

    # 5. Check OrderRepository.java Content (10 pts)
    repo_content = result.get('repository_java_content', '')
    if repo_content:
        # Look for "findById(long id)" or "findById(Long id)"
        has_long_param = bool(re.search(r'findById\s*\(\s*(long|Long)\s+\w+\s*\)', repo_content))
        
        if has_long_param:
            score += 10
            feedback_parts.append("OrderRepository.java: findById updated to accept long")
        else:
            feedback_parts.append("OrderRepository.java: findById not updated")
    else:
        feedback_parts.append("OrderRepository.java content missing")

    # 6. Anti-gaming check
    if not result.get('file_modified_during_task', False):
        feedback_parts.append("WARNING: Order.java was not modified during task execution")
        # If files weren't modified but somehow match requirements (e.g., initial state was wrong), fail
        if score > 0:
            score = 0
            feedback_parts.append("FAILED: No changes detected to source files")

    # 7. VLM Verification (Supplementary)
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        prompt = """
        You are verifying a software refactoring task in IntelliJ IDEA.
        The user should be using the 'Type Migration' dialog.
        
        Look for:
        1. A dialog titled 'Type Migration' or 'Refactoring'.
        2. Code being edited in Order.java.
        3. 'int id' being changed to 'long id'.
        
        Did the agent perform the refactoring steps?
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                # We don't change score based on VLM for this code task, just append feedback
                feedback_parts.append(f"VLM Analysis: {vlm_res.get('parsed', {}).get('summary', 'Workflow observed')}")
        except Exception:
            pass

    success = score >= 70
    return {
        "passed": success,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }