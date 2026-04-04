#!/usr/bin/env python3
"""
Verifier for reformat_and_export_dicom_series task.

Scoring (100 points total):
1. Output directory exists: 10 pts
2. Contains significant number of files (>50): 20 pts
3. Files were created during task (anti-gaming): 10 pts
4. Files are valid DICOMs: 20 pts
5. Content differs from source (proof of reorientation): 40 pts

Pass threshold: 80 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reformat_dicom(traj, env_info, task_info):
    """Verify DICOM reorientation and export."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification infrastructure error (copy_from_env missing)"}

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    score = 0
    feedback = []
    
    # 1. Output Directory
    if result.get("output_dir_exists"):
        score += 10
        feedback.append("Output directory found")
    else:
        feedback.append("Output directory '/home/ga/Documents/reoriented_dicom/' not found")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # 2. File Count
    count = result.get("file_count", 0)
    if count > 50:
        score += 20
        feedback.append(f"File count sufficient ({count})")
    elif count > 0:
        score += 10
        feedback.append(f"File count low ({count}), expected > 50")
    else:
        feedback.append("No files found in output directory")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # 3. Created During Task
    if result.get("files_created_during_task"):
        score += 10
        feedback.append("Files created during task session")
    else:
        feedback.append("Files have old timestamps (pre-dating task)")

    # 4. Valid DICOMs
    valid_count = result.get("valid_dicom_count", 0)
    if valid_count > 0 and valid_count >= (count * 0.9): # Allow 10% non-dicom noise
        score += 20
        feedback.append("Files verified as valid DICOM")
    elif valid_count > 0:
        score += 10
        feedback.append(f"Some files valid DICOM ({valid_count}/{count})")
    else:
        feedback.append("Files are NOT valid DICOM format")
        
    # 5. Content Modification (Proof of Reorientation)
    if result.get("content_modified"):
        score += 40
        feedback.append("Data content modified (reorientation confirmed)")
    else:
        feedback.append("Output data matches source identicaly (looks like a copy, not a reformat)")
        
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }