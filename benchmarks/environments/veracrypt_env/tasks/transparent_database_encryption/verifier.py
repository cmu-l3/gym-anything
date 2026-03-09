#!/usr/bin/env python3
"""
Verifier for transparent_database_encryption task.

Criteria:
1. Encrypted volume exists (20 pts)
2. Volume is mounted at the correct secure path (20 pts)
3. Original database path is now a symlink (20 pts)
4. Symlink points to the mounted volume (20 pts)
5. Database is readable/writable via the symlink (20 pts)

Anti-gaming:
- Checks timestamps (files created during task) - handled implicitly by checking state change
- Verifies database content integrity (count > 0)
- Ensures data isn't just a copy on the unencrypted disk (check symlink target)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transparent_encryption(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: Volume Creation (20 pts)
    if result.get("volume_exists"):
        score += 20
        feedback_parts.append("Encrypted volume created")
    else:
        feedback_parts.append("Encrypted volume file missing")

    # Criterion 2: Volume Mount (20 pts)
    if result.get("mount_active") and result.get("encryption_confirmed"):
        score += 20
        feedback_parts.append("Volume mounted securely")
    elif result.get("mount_active"):
        score += 10
        feedback_parts.append("Volume mounted but not confirmed as VeraCrypt volume")
    else:
        feedback_parts.append("Target mount point is not active")

    # Criterion 3: Symlink Creation (20 pts)
    if result.get("is_symlink"):
        score += 20
        feedback_parts.append("Symlink established at original path")
    else:
        feedback_parts.append("Original path is not a symlink")

    # Criterion 4: Link Target (20 pts)
    # The link must point to the secure mount location
    if result.get("secure_location"):
        score += 20
        feedback_parts.append("Symlink points to encrypted volume")
    else:
        target = result.get("link_target", "none")
        feedback_parts.append(f"Symlink points to insecure location: {target}")

    # Criterion 5: Data Integrity (20 pts)
    readable = result.get("db_readable")
    writable = result.get("db_writable")
    count = result.get("record_count", 0)
    
    if readable and writable and count >= 100:
        score += 20
        feedback_parts.append(f"Database fully functional ({count} records)")
    elif readable:
        score += 10
        feedback_parts.append("Database readable but write check failed")
    else:
        feedback_parts.append("Database not readable via symlink")

    # Final calculation
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }