#!/usr/bin/env python3
"""
Verifier for sort_and_mount_archives_by_content task.

Goal:
- Slot 11 should contain the volume with 'financial_records.csv'.
- Slot 22 should contain the volume with 'legal_contract.txt'.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sort_and_mount(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Verify Slot 11 (Financial)
    s11_mounted = result.get('slot11_mounted', False)
    s11_content = result.get('slot11_content', 'unknown')
    
    if s11_mounted:
        score += 10
        if s11_content == 'financial':
            score += 40
            feedback_parts.append("✅ Slot 11: Correctly contains Financial Records")
        elif s11_content == 'legal':
            feedback_parts.append("❌ Slot 11: Incorrectly contains Legal Contracts")
        elif s11_content == 'obsolete':
            feedback_parts.append("❌ Slot 11: Incorrectly contains Obsolete Notes")
        else:
            feedback_parts.append(f"❌ Slot 11: Content unknown or empty ({s11_content})")
    else:
        feedback_parts.append("❌ Slot 11: Nothing mounted")

    # Verify Slot 22 (Legal)
    s22_mounted = result.get('slot22_mounted', False)
    s22_content = result.get('slot22_content', 'unknown')
    
    if s22_mounted:
        score += 10
        if s22_content == 'legal':
            score += 40
            feedback_parts.append("✅ Slot 22: Correctly contains Legal Contracts")
        elif s22_content == 'financial':
            feedback_parts.append("❌ Slot 22: Incorrectly contains Financial Records")
        elif s22_content == 'obsolete':
            feedback_parts.append("❌ Slot 22: Incorrectly contains Obsolete Notes")
        else:
            feedback_parts.append(f"❌ Slot 22: Content unknown or empty ({s22_content})")
    else:
        feedback_parts.append("❌ Slot 22: Nothing mounted")

    # Optional: Bonus check for cleanliness (obsolete not mounted)
    # Not strictly penalized in score, just feedback
    total_mounted = result.get('total_mounted_count', 0)
    expected_count = 2 if (s11_mounted and s22_mounted) else (1 if (s11_mounted or s22_mounted) else 0)
    
    if total_mounted > expected_count:
        feedback_parts.append(f"⚠️ Warning: {total_mounted} volumes mounted (expected {expected_count})")
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }