#!/usr/bin/env python3
"""
Verifier for create_kpi_dashboard_slide task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kpi_dashboard(traj, env_info, task_info):
    """
    Verify that the KPI dashboard slide was created with correct data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    initial_slide_count = metadata.get('initial_slide_count', 4)
    expected_slide_count = metadata.get('expected_slide_count', 5)

    # Copy result file
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

    # Extract data
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    analysis = result.get('analysis', {})
    
    # Error check
    if analysis.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Analysis error: {analysis['error']}"}

    current_slide_count = analysis.get('slide_count', 0)
    values_found = analysis.get('values_found', {})
    original_preserved = analysis.get('original_content_preserved', False)
    kpi_title_found = analysis.get('kpi_title_found', False)

    score = 0
    feedback_parts = []
    
    # Check 1: File integrity (10 pts)
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File modified")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but not modified")
    else:
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    # Check 2: Slide count (15 pts)
    if current_slide_count == expected_slide_count:
        score += 15
        feedback_parts.append("Slide count correct (5)")
    elif current_slide_count > initial_slide_count:
        score += 10
        feedback_parts.append(f"Slide count increased ({current_slide_count})")
    else:
        feedback_parts.append(f"No new slides added (Count: {current_slide_count})")

    # Check 3: Original content (5 pts)
    if original_preserved:
        score += 5
        feedback_parts.append("Original slides preserved")
    else:
        feedback_parts.append("Original content damaged")

    # Check 4: Title (15 pts)
    if kpi_title_found:
        score += 15
        feedback_parts.append("KPI title found")
    else:
        feedback_parts.append("KPI title missing")

    # Check 5: Data values (55 pts total)
    # Carbon (15), Energy (15), Water (15), Waste (10)
    
    kpi_scores = {
        "carbon": 15,
        "energy": 15,
        "water": 15,
        "waste": 10
    }
    
    for key, points in kpi_scores.items():
        if values_found.get(key, False):
            score += points
            feedback_parts.append(f"{key.title()} value correct")
        else:
            feedback_parts.append(f"{key.title()} value missing")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }