#!/usr/bin/env python3
"""
Verifier for reformat_volume_filesystem task.

Scoring Criteria:
1. Volume Mountability (10 pts)
2. Filesystem Conversion to ext4 (30 pts)
3. Data Preservation (Integrity) (30 pts)
4. Report Creation (15 pts)
5. Clean Cleanup (Dismounted) (5 pts)
6. VLM Verification (10 pts)
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reformat_volume_filesystem(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score: Volume Mountable (10 pts)
    if result.get('volume_mountable'):
        score += 10
        feedback_parts.append("✅ Volume is mountable with correct password")
    else:
        feedback_parts.append("❌ Volume could not be mounted (password changed or volume corrupted)")

    # 3. Score: Filesystem Type (30 pts)
    fs_type = result.get('filesystem_type', 'unknown')
    if fs_type == 'ext4':
        score += 30
        feedback_parts.append("✅ Filesystem converted to ext4")
    elif fs_type in ['vfat', 'fat']:
        feedback_parts.append("❌ Filesystem is still FAT")
    else:
        feedback_parts.append(f"❌ Filesystem is {fs_type} (expected ext4)")

    # 4. Score: Data Preservation (30 pts)
    if result.get('checksums_match'):
        score += 30
        feedback_parts.append("✅ All data preserved with data integrity")
    elif result.get('files_preserved'):
        score += 15
        feedback_parts.append("⚠️ Files present but checksums mismatch (content modified)")
    else:
        feedback_parts.append("❌ Data lost or files missing")

    # 5. Score: Report (15 pts)
    if result.get('report_exists'):
        if result.get('report_content_valid'):
            score += 15
            feedback_parts.append("✅ Report created and valid")
        else:
            score += 5
            feedback_parts.append("⚠️ Report exists but content incomplete")
    else:
        feedback_parts.append("❌ Report file missing")

    # 6. Score: Clean State (5 pts)
    if not result.get('agent_left_mounted'):
        score += 5
        feedback_parts.append("✅ Cleaned up (volumes dismounted)")
    else:
        feedback_parts.append("⚠️ Failed to dismount volume at end")

    # 7. VLM Verification (10 pts)
    # Check if we see terminal commands related to mkfs or VeraCrypt properties showing ext4
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot and env_info.get('query_vlm'):
        prompt = """
        Verify if the user has reformatted a VeraCrypt volume to ext4.
        Look for:
        1. Terminal output showing 'mkfs.ext4' or 'sudo mkfs -t ext4'
        2. VeraCrypt window showing properties of a mounted volume as 'Ext4'
        3. A text editor showing a report about the filesystem
        
        Is there evidence of ext4 formatting?
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
             score += 10
             feedback_parts.append("✅ VLM visual verification passed")
        else:
             # If programmatic check passed, we give points anyway to avoid false negative
             if fs_type == 'ext4':
                 score += 10
                 feedback_parts.append("✅ VLM inferred success from state")
             else:
                 feedback_parts.append("❌ No visual evidence of work")
    else:
        # Fallback if VLM unavailable but task passed programmatically
        if score >= 70:
            score += 10

    passed = score >= 70 and fs_type == 'ext4' and result.get('checksums_match')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }