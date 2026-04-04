#!/usr/bin/env python3
"""
Verifier for repair_encrypted_filesystem task.

SCORING CRITERIA:
1. Recovery directory and file existence (10 pts)
2. File content integrity check (MD5) (40 pts) - Proves decryption + data extraction
3. File timestamp validity (10 pts) - Proves work done during task
4. Volume integrity (40 pts) - Proves the filesystem was actually repaired (mountable)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repair_encrypted_filesystem(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_md5 = metadata.get('file_content_md5', 'e5828c564f71fea3a12dac8c643933f8')
    
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
    
    # Criterion 1: File Existence (10 pts)
    if result.get('file_exists'):
        score += 10
        feedback_parts.append("Recovered file exists")
    else:
        feedback_parts.append("Recovered file NOT found")
        return {"passed": False, "score": 0, "feedback": "File not recovered"}

    # Criterion 2: Content Integrity (40 pts)
    actual_hash = result.get('file_hash', '')
    if actual_hash == expected_md5:
        score += 40
        feedback_parts.append("File content correct")
    else:
        feedback_parts.append(f"File content corrupted (Hash mismatch: {actual_hash})")

    # Criterion 3: Timestamp (10 pts)
    if result.get('created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task")

    # Criterion 4: Volume Repaired (40 pts)
    # The ultimate test: can the volume be mounted normally now?
    if result.get('volume_repaired'):
        score += 40
        feedback_parts.append("Volume filesystem successfully repaired")
    else:
        feedback_parts.append("Volume is still not mountable normally (filesystem not fully repaired)")

    passed = score >= 80  # Needs file recovery + content + repair (10+40+40=90) or file+content+time+partial repair
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }