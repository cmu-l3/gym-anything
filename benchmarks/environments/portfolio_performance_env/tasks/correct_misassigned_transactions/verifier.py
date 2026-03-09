#!/usr/bin/env python3
"""Verifier for correct_misassigned_transactions task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_misassigned_transactions(traj, env_info, task_info):
    """
    Verify that NVDA/AMD transactions were moved to Speculative Tech account
    and BND transactions remained in Retirement Savings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    feedback = []
    
    # Check file modification (10 pts)
    if result.get('file_modified'):
        score += 10
        feedback.append("Portfolio file saved")
    else:
        feedback.append("Portfolio file NOT saved")

    # Check Data Integrity (10 pts) - Total transactions should still be 6
    total_txns = result.get('total_txns', 0)
    if total_txns == 6:
        score += 10
        feedback.append("Transaction count preserved (6)")
    else:
        feedback.append(f"Transaction count changed: {total_txns} (expected 6)")

    # Check NVDA Move (30 pts)
    # Expect: 0 in Retirement, 2 in Speculative
    ret_nvda = result.get('retirement_nvda_count', 0)
    spec_nvda = result.get('speculative_nvda_count', 0)
    
    if ret_nvda == 0 and spec_nvda == 2:
        score += 30
        feedback.append("NVIDIA transactions correctly moved to Speculative")
    elif spec_nvda > 0:
        score += 15
        feedback.append(f"Some NVIDIA transactions moved ({spec_nvda}/2)")
    else:
        feedback.append("NVIDIA transactions NOT moved")

    # Check AMD Move (30 pts)
    # Expect: 0 in Retirement, 2 in Speculative
    ret_amd = result.get('retirement_amd_count', 0)
    spec_amd = result.get('speculative_amd_count', 0)
    
    if ret_amd == 0 and spec_amd == 2:
        score += 30
        feedback.append("AMD transactions correctly moved to Speculative")
    elif spec_amd > 0:
        score += 15
        feedback.append(f"Some AMD transactions moved ({spec_amd}/2)")
    else:
        feedback.append("AMD transactions NOT moved")

    # Check BND Retention (20 pts)
    # Expect: 2 in Retirement, 0 in Speculative
    ret_bnd = result.get('retirement_bnd_count', 0)
    spec_bnd = result.get('speculative_bnd_count', 0)
    
    if ret_bnd == 2 and spec_bnd == 0:
        score += 20
        feedback.append("Bond transactions correctly kept in Retirement")
    elif ret_bnd < 2:
        feedback.append("Some Bond transactions were moved or lost")
    else:
        feedback.append("Bond transactions retained")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }