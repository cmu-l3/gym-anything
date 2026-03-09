#!/usr/bin/env python3
"""
Verifier for prepare_volume_for_distribution task.

Criteria:
1. Clone Creation: 'financial_transfer.hc' exists and is a distinct file.
2. Re-keying: Clone accepts NEW password/PIM, rejects OLD password.
3. Master Integrity: Original volume still accepts OLD password.
4. Content: Clone contains original data + new transmittal notice.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_volume_for_distribution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Retrieve result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Clone Created (10 pts)
    if result.get('clone_exists') and result.get('clone_is_distinct_file') and result.get('created_during_task'):
        score += 10
        feedback_parts.append("✅ Clone created")
    elif result.get('clone_exists'):
        score += 5
        feedback_parts.append("⚠️ Clone exists but timestamp/file check suspicious")
    else:
        feedback_parts.append("❌ Clone file missing")

    # 2. Re-keying Success (30 pts)
    # Clone must open with NEW creds
    if result.get('clone_accepts_new_creds'):
        score += 30
        feedback_parts.append("✅ Clone password/PIM changed successfully")
    else:
        feedback_parts.append("❌ Clone does not open with new credentials")

    # 3. Security Check (15 pts)
    # Clone must NOT open with OLD creds
    if result.get('clone_rejects_old_creds'):
        score += 15
        feedback_parts.append("✅ Old credentials removed from clone")
    else:
        feedback_parts.append("❌ Clone still opens with old password")

    # 4. Master Integrity (15 pts)
    # Master must still open with OLD creds
    if result.get('master_integrity_ok'):
        score += 15
        feedback_parts.append("✅ Master volume intact")
    else:
        feedback_parts.append("❌ Master volume altered/corrupted")

    # 5. Data Preservation (15 pts)
    if result.get('data_preserved'):
        score += 15
        feedback_parts.append("✅ Original data verified in clone")
    else:
        feedback_parts.append("❌ Data missing from clone")

    # 6. Notice Added (15 pts)
    if result.get('notice_content_correct'):
        score += 15
        feedback_parts.append("✅ Transmittal notice correct")
    elif result.get('notice_file_exists'):
        score += 10
        feedback_parts.append("⚠️ Transmittal notice exists but content incorrect")
    else:
        feedback_parts.append("❌ Transmittal notice missing")

    # Final Calculation
    passed = score >= 70 and result.get('clone_accepts_new_creds')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }