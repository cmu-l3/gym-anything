#!/usr/bin/env python3
"""
Verifier for migrate_volume_twofish task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_volume_twofish(traj, env_info, task_info):
    """
    Verify the migration of files to a Twofish encrypted volume.
    
    Scoring Criteria:
    1. New volume exists and valid size (8 pts)
    2. Created during task (anti-gaming) (5 pts)
    3. Correct Encryption (Twofish) (15 pts)
    4. Mounts with correct password (7 pts)
    5. Files migrated correctly (checking name and size against GT) (36 pts)
    6. Manifest exists and content matches (14 pts)
    7. Clean dismount (10 pts)
    8. Source intact (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve result from container
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

    # 1. Volume Existence & Size
    if result.get('volume_exists'):
        size = result.get('volume_size', 0)
        # Expecting around 25MB (25 * 1024 * 1024 = ~26M)
        if size >= 20 * 1024 * 1024:
            score += 8
            feedback_parts.append("Destination volume exists with correct size")
        else:
            feedback_parts.append(f"Destination volume too small ({size} bytes)")
    else:
        feedback_parts.append("Destination volume not found")

    # 2. Anti-gaming (Time)
    if result.get('created_during_task'):
        score += 5
    else:
        if result.get('volume_exists'):
            feedback_parts.append("Volume created before task start")

    # 3. Encryption Algo
    if result.get('is_twofish'):
        score += 15
        feedback_parts.append("Correct encryption (Twofish)")
    elif result.get('is_mountable'):
        feedback_parts.append("Incorrect encryption algorithm (not Twofish)")

    # 4. Mountability
    if result.get('is_mountable'):
        score += 7
        feedback_parts.append("Volume mounts with correct password")
    else:
        feedback_parts.append("Failed to mount volume with provided password")

    # 5. File Migration Content
    ground_truth = result.get('ground_truth', {})
    files_found = result.get('files_found', [])
    files_found_map = {f['name']: f['size'] for f in files_found}
    
    migrated_count = 0
    expected_count = len(ground_truth)
    
    for fname, fsize in ground_truth.items():
        if fname in files_found_map:
            # Check size tolerance (exact match preferred for copy)
            if files_found_map[fname] == fsize:
                score += 12
                migrated_count += 1
            else:
                score += 6 # Partial credit for correct name but wrong size
                feedback_parts.append(f"File {fname} size mismatch")
        else:
            feedback_parts.append(f"Missing file: {fname}")
            
    if migrated_count == expected_count and expected_count > 0:
        feedback_parts.append("All files migrated successfully")

    # 6. Manifest
    if result.get('manifest_exists'):
        score += 5
        content = result.get('manifest_content', '')
        # Check if manifest contains filenames
        manifest_matches = 0
        for fname in ground_truth.keys():
            if fname in content:
                manifest_matches += 1
        
        # 9 points for manifest content (3 per file)
        score += (manifest_matches * 3)
        if manifest_matches == expected_count:
            feedback_parts.append("Manifest contains all filenames")
    else:
        feedback_parts.append("Migration manifest missing")

    # 7. Dismount State
    if result.get('all_dismounted'):
        score += 10
        feedback_parts.append("All volumes cleanly dismounted")
    else:
        feedback_parts.append("Volumes left mounted")

    # 8. Source Intact
    if result.get('source_intact'):
        score += 5
    else:
        feedback_parts.append("Source volume corrupted or inaccessible")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }