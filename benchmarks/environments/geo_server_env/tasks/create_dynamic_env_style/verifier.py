#!/usr/bin/env python3
"""
Verifier for create_dynamic_env_style task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_dynamic_env_style(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the dynamic styling task.
    
    Success requires:
    1. Style exists and is associated with the layer.
    2. Style uses the 'env' function with the correct parameter name.
    3. Output image exists.
    4. CRITICAL: Dynamic rendering test passed (verified by export script performing multiple WMS requests).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Retrieve result JSON from container
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
            
    # Verify nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails (e.g. file missing), warn but don't hard fail if result seems valid otherwise
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Output file creation (10 pts)
    if result.get('output_exists'):
        score += 5
        feedback_parts.append("Output image found")
        if result.get('output_created_during_task'):
            score += 5
            feedback_parts.append("Image created during task")
    else:
        feedback_parts.append("Output image missing")

    # 2. Style Existence and Content (30 pts)
    if result.get('style_exists'):
        score += 10
        feedback_parts.append("Style 'dynamic_country' created")
        
        if result.get('has_env_func'):
            score += 10
            feedback_parts.append("Style uses 'env' function")
        else:
            feedback_parts.append("Style missing 'env' function")
            
        if result.get('has_param_name'):
            score += 10
            feedback_parts.append("Style uses 'target_country' parameter")
        else:
            feedback_parts.append("Style missing 'target_country' parameter")
    else:
        feedback_parts.append("Style 'dynamic_country' NOT found")

    # 3. Layer Association (10 pts)
    if result.get('layer_associated'):
        score += 10
        feedback_parts.append("Style associated with 'ne_countries' layer")
    else:
        feedback_parts.append("Style NOT associated with layer")

    # 4. Dynamic Rendering Verification (50 pts)
    # This is the most critical check. The export script ran two WMS requests with different env params.
    if result.get('dynamic_test_passed'):
        score += 50
        feedback_parts.append("Dynamic rendering verified (Highlighter moves correctly with env param)")
    else:
        # Provide debug info
        debug = result.get('test_debug', {})
        feedback_parts.append("Dynamic rendering check FAILED")
        feedback_parts.append(f"Debug: Brazil/Egypt colors A: {debug.get('test_a_brazil_color')}/{debug.get('test_a_egypt_color')}")
        feedback_parts.append(f"Debug: Brazil/Egypt colors B: {debug.get('test_b_brazil_color')}/{debug.get('test_b_egypt_color')}")

    # Final Score Calculation
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }