#!/usr/bin/env python3
"""
Verifier for flatfield_illumination_correction task.

Scoring Criteria:
1. Files Exist (40 pts):
   - Corrected Image (10)
   - Flat-field Reference (10)
   - CSV Report (10)
   - Summary Text (10)
2. Timestamps Valid (10 pts): Files created during task.
3. Quality Checks (50 pts):
   - Flat-field reference is smooth (indicates blur used) (15)
   - Uniformity Ratio improved (closer to 1.0) (20)
   - CV improved (lower variation) (15)

Total: 100 points. Pass: 60 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flatfield_correction(traj, env_info, task_info):
    # 1. Retrieve result via copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

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
    
    analysis = result.get("analysis", {})
    
    # --- Criterion 1: Files Exist (40 pts) ---
    files = {
        "corrected_image": 10,
        "flatfield_reference": 10,
        "uniformity_report": 10,
        "correction_summary": 10
    }
    
    files_exist_score = 0
    for fname, pts in files.items():
        finfo = result.get(fname, {})
        if finfo.get("exists", False):
            files_exist_score += pts
            
    score += files_exist_score
    feedback_parts.append(f"Files found: {files_exist_score}/40 pts")

    # --- Criterion 2: Timestamps (10 pts) ---
    # Give full points if at least 2 key files were created during task
    created_count = 0
    for fname in files.keys():
        if result.get(fname, {}).get("created_during_task", False):
            created_count += 1
            
    if created_count >= 2:
        score += 10
        feedback_parts.append("Files created during task: 10/10 pts")
    elif created_count > 0:
        score += 5
        feedback_parts.append("Some files created during task: 5/10 pts")
    else:
        feedback_parts.append("No files created during task: 0/10 pts")

    # --- Criterion 3: Quality Checks (50 pts) ---
    
    # Smooth Reference (15 pts)
    if analysis.get("reference_image_smooth", False):
        score += 15
        feedback_parts.append("Flat-field reference is smooth (Gaussian blur applied): 15/15 pts")
    else:
        feedback_parts.append("Flat-field reference not smooth enough: 0/15 pts")

    # Uniformity Improvement (20 pts)
    if analysis.get("ratio_improved", False):
        score += 20
        feedback_parts.append("Uniformity ratio improved (closer to 1.0): 20/20 pts")
    else:
        # Check if ratio is reasonable even if improvement check strictly failed
        # (e.g. if initial was already good, though unlikely with setup script)
        ratio = analysis.get("measured_ratio", 0)
        if 0.85 < ratio < 1.15:
             score += 10
             feedback_parts.append("Uniformity ratio is good (>0.85): 10/20 pts")
        else:
             feedback_parts.append("Uniformity ratio did not improve: 0/20 pts")

    # CV Improvement (15 pts)
    if analysis.get("cv_improved", False):
        score += 15
        feedback_parts.append("Coefficient of Variation improved: 15/15 pts")
    else:
        feedback_parts.append("CV did not improve: 0/15 pts")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "analysis": analysis,
            "measured_ratio": analysis.get("measured_ratio"),
            "measured_cv": analysis.get("measured_cv")
        }
    }