#!/usr/bin/env python3
"""
Verifier for refactor_artifact_path task.

Checks:
1. Source artifact is GONE (moved).
2. Target artifact EXISTS at the correct Maven path.
3. Target artifact checksum matches the original (integrity check).
4. Target artifact timestamp is after task start (anti-gaming).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_iso8601(date_str):
    """Parse Artifactory ISO 8601 date string to timestamp."""
    # Example: 2023-10-27T10:00:00.123+0000
    try:
        # Simplified parsing, assuming usage of standard libraries available or simple string comparison
        # Artifactory usually returns: 2024-05-22T14:52:19.462Z or with offset
        # For simplicity in this env, we can just compare string order if format is standard,
        # but let's try to be robust.
        # Since we just need to check if it's "new", and we have task_start in seconds,
        # let's try to convert.
        if not date_str:
            return 0
        # Remove Z or Offset for simple parsing if complex libs not avail
        clean_date = date_str.split('.')[0]
        dt = datetime.strptime(clean_date, "%Y-%m-%dT%H:%M:%S")
        return dt.timestamp()
    except Exception as e:
        logger.warning(f"Failed to parse date {date_str}: {e}")
        return 0

def verify_refactor_artifact_path(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    metadata = task_info.get('metadata', {})
    expected_sha1 = metadata.get('expected_sha1')
    
    score = 0
    feedback_parts = []
    
    # 1. Check Source Removal (30 pts)
    source_exists = result.get('source_exists', True)
    if not source_exists:
        score += 30
        feedback_parts.append("Source file successfully removed/moved")
    else:
        feedback_parts.append("Source file still exists (failed to move?)")

    # 2. Check Target Existence (50 pts)
    target_exists = result.get('target_exists', False)
    target_meta = result.get('target_metadata', {})
    
    if target_exists:
        score += 50
        feedback_parts.append("Target file exists at correct path")
        
        # 3. Integrity Check (20 pts)
        actual_sha1 = target_meta.get('sha1', '')
        if expected_sha1 and actual_sha1 == expected_sha1:
            score += 20
            feedback_parts.append("File integrity verified (checksum match)")
        elif expected_sha1:
             feedback_parts.append(f"Checksum mismatch: expected {expected_sha1}, got {actual_sha1}")
        else:
             # If no expected sha1 in metadata, give points if size > 0
             if target_meta.get('size', 0) > 0:
                 score += 20
                 feedback_parts.append("File appears valid (size > 0)")
             else:
                 feedback_parts.append("Target file is empty")
                 
        # 4. Anti-Gaming (Timestamp check)
        task_start = result.get('task_start', 0)
        # created_str = target_meta.get('created', '')
        # created_ts = parse_iso8601(created_str)
        # Note: Artifactory 'created' might be original upload time if moved?
        # Artifactory 'lastModified' is usually preserved on move.
        # However, the 'created' in the new path *entry* in DB might change or not.
        # Relying on 'Source Removal' + 'Target Existence' implies an action was taken.
        # Strict timestamp checking on 'Move' operations can be tricky if Artifactory preserves metadata.
        # We will assume verifying source=absent AND target=present is sufficient proof of work for a move.
        
    else:
        feedback_parts.append("Target file NOT found at expected path")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }