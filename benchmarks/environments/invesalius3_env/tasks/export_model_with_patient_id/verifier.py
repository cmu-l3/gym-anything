#!/usr/bin/env python3
"""
Verifier for export_model_with_patient_id task.

Scoring (100 points total):
  - STL file exists with valid size (>100KB):      30 pts
  - Filename contains correct Patient ID:          50 pts
  - Filename has correct suffix (_Skull.stl):      10 pts
  - File created during task session:              10 pts

Pass threshold: 80 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_export_model_with_patient_id(traj, env_info, task_info):
    """Verify that the exported STL file contains the Patient ID."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_model_with_patient_id_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    gt_id = result.get("ground_truth_id", "unknown")
    files_found = result.get("files_found", [])
    
    if not files_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No STL files found in Documents folder."
        }
        
    # Find the best scoring file if multiple exist
    best_file_score = 0
    best_file_feedback = []
    
    # Evaluate each file, take the max score
    for f in files_found:
        current_score = 0
        current_feedback = []
        
        # Criterion 1: Valid STL file (Size)
        if f.get("is_valid_size"):
            current_score += 30
            current_feedback.append("STL created")
        else:
            current_feedback.append("File too small/empty")
            
        # Criterion 2: Contains Patient ID
        if f.get("contains_id"):
            current_score += 50
            current_feedback.append(f"ID '{gt_id}' found in name")
        else:
            current_feedback.append(f"ID '{gt_id}' missing from name")
            
        # Criterion 3: Correct Suffix
        if f.get("has_correct_suffix"):
            current_score += 10
            current_feedback.append("Suffix '_Skull.stl' correct")
        else:
            current_feedback.append("Suffix incorrect")
            
        # Criterion 4: Anti-gaming (Freshness)
        if f.get("is_fresh"):
            current_score += 10
            current_feedback.append("New file")
        else:
            current_feedback.append("Old file (anti-gaming fail)")
            
        if current_score > best_file_score:
            best_file_score = current_score
            best_file_feedback = current_feedback

    # Final result
    passed = best_file_score >= 80
    feedback_str = f"Best file: {', '.join(best_file_feedback)}"
    
    return {
        "passed": passed,
        "score": best_file_score,
        "feedback": feedback_str,
        "details": {
            "ground_truth_id": gt_id,
            "files_checked": len(files_found)
        }
    }