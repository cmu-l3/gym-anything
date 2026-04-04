#!/usr/bin/env python3
"""
Verifier for annotate_wells_with_elevation task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_annotate_wells_with_elevation(traj, env_info, task_info):
    """
    Verify that monitoring wells were annotated with elevation data.
    
    Scoring Criteria:
    1. Output file exists (15 pts)
    2. File created during task (anti-gaming) (10 pts)
    3. Valid GeoJSON & Feature Count preserved (15 pts)
    4. Elevation field added (20 pts)
    5. Data Accuracy (Sampled values match raster) (40 pts)
    
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file
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
            
    analysis = result.get("verification_analysis", {})
    
    score = 0
    feedback = []
    
    # 1. Output Exists
    if result.get("output_exists", False):
        score += 15
        feedback.append("Output file found")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
    # 2. Created During Task
    if result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task")
    else:
        feedback.append("File timestamp indicates it was not created during this session")
        
    # 3. Structure & Count
    if analysis.get("valid_geojson", False):
        count = analysis.get("feature_count", 0)
        # We generated 15 points in setup
        if count == 15:
            score += 15
            feedback.append(f"Feature count preserved ({count})")
        else:
            score += 5
            feedback.append(f"Feature count mismatch (Found {count}, expected 15)")
    else:
        feedback.append("Invalid GeoJSON structure")
        
    # 4. Elevation Field
    if analysis.get("has_elevation_field", False):
        score += 20
        feedback.append("New attribute field found")
    else:
        feedback.append("No new numeric attribute field found")
        
    # 5. Data Accuracy
    acc_score = analysis.get("accuracy_score", 0)
    score += (acc_score * 0.4) # Scale 100 to 40 pts
    
    avg_error = analysis.get("avg_error", 9999)
    if avg_error < 1.0:
        feedback.append("Sampled values are accurate")
    else:
        feedback.append(f"Sampled values have high error (avg deviation: {avg_error:.2f})")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }