#!/usr/bin/env python3
"""
Verifier for Configure Store Shipping task.

Scoring (100 points):
1. Standard Ground Shipping exists (15pts)
2. Standard rate is $7.99 (20pts)
3. Express Overnight Shipping exists (15pts)
4. Express rate is $19.99 (20pts)
5. Both assigned to Urban Electronics store (15pts)
6. Both methods enabled (15pts)

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_store_shipping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # Helper to check rate equality with small epsilon
        def check_rate(actual_str, expected_float):
            try:
                return abs(float(actual_str) - expected_float) < 0.01
            except (ValueError, TypeError):
                return False

        # --- Standard Ground Checks ---
        std = result.get('standard', {})
        if std.get('found'):
            score += 15
            feedback_parts.append("Standard Ground method created")
            
            # Rate check
            if check_rate(std.get('rate'), 7.99):
                score += 20
                feedback_parts.append("Standard rate correct ($7.99)")
            else:
                feedback_parts.append(f"Standard rate incorrect (found ${std.get('rate', '0')})")
        else:
            feedback_parts.append("Standard Ground method NOT found")

        # --- Express Overnight Checks ---
        exp = result.get('express', {})
        if exp.get('found'):
            score += 15
            feedback_parts.append("Express Overnight method created")
            
            # Rate check
            if check_rate(exp.get('rate'), 19.99):
                score += 20
                feedback_parts.append("Express rate correct ($19.99)")
            else:
                feedback_parts.append(f"Express rate incorrect (found ${exp.get('rate', '0')})")
        else:
            feedback_parts.append("Express Overnight method NOT found")

        # --- Store Assignment Checks (15 pts total) ---
        # Partial credit if one is correct
        std_store = std.get('store_assigned', False)
        exp_store = exp.get('store_assigned', False)
        
        if std_store and exp_store:
            score += 15
            feedback_parts.append("Both methods assigned to store")
        elif std_store or exp_store:
            score += 7
            feedback_parts.append("Only one method assigned to store")
        else:
            feedback_parts.append("Store assignment missing")

        # --- Status Checks (15 pts total) ---
        # Status '1' is enabled
        std_enabled = str(std.get('status', '0')) == '1'
        exp_enabled = str(exp.get('status', '0')) == '1'
        
        if std_enabled and exp_enabled:
            score += 15
            feedback_parts.append("Both methods enabled")
        elif std_enabled or exp_enabled:
            score += 7
            feedback_parts.append("Only one method enabled")
        else:
            feedback_parts.append("Methods created but not enabled")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }