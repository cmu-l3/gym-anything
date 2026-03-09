#!/usr/bin/env python3
"""
Verifier for export_axial_tiff_stack task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_axial_tiff_stack(traj, env_info, task_info):
    """
    Verify that the agent exported the axial slices as a stack of TIFF images.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_count = metadata.get('min_count', 100)
    max_count = metadata.get('max_count', 120)
    
    # Retrieve result file
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
    
    # 1. Directory Existence (10 pts)
    if result.get("directory_exists", False):
        score += 10
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("Output directory not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File Presence (15 pts)
    file_count = result.get("file_count", 0)
    if file_count > 0:
        score += 15
        feedback_parts.append(f"Found {file_count} files")
    else:
        feedback_parts.append("Directory is empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. TIFF Format Validity (20 pts)
    tiff_count = result.get("tiff_valid_count", 0)
    # Allow a small margin of error (e.g. 90% are valid TIFFs)
    if file_count > 0 and (tiff_count / file_count) >= 0.9:
        score += 20
        feedback_parts.append("Valid TIFF format confirmed")
    elif tiff_count > 0:
        score += 10
        feedback_parts.append(f"Mixed/Partial TIFFs ({tiff_count}/{file_count})")
    else:
        feedback_parts.append("No valid TIFF headers found")

    # 4. Slice Count Accuracy (25 pts)
    # Target is ~108 slices.
    if min_count <= tiff_count <= max_count:
        score += 25
        feedback_parts.append("Slice count correct")
    elif tiff_count > 0:
        feedback_parts.append(f"Incorrect slice count: {tiff_count} (expected {min_count}-{max_count})")

    # 5. Non-Trivial Files (15 pts)
    non_trivial = result.get("non_trivial_files", 0)
    if file_count > 0 and (non_trivial / file_count) >= 0.9:
        score += 15
        feedback_parts.append("Files contain data")
    else:
        feedback_parts.append("Files appear empty or too small")

    # 6. Anti-Gaming / Timestamps (15 pts)
    created_during = result.get("files_created_during_task", 0)
    if file_count > 0 and (created_during / file_count) >= 0.9:
        score += 15
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Files have old timestamps (pre-existing?)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }