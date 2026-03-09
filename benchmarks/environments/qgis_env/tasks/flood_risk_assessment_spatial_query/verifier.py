#!/usr/bin/env python3
"""
Verifier for flood_risk_assessment_spatial_query task.

Checks:
1. Output file exists and was created during the task.
2. Output contains specific at-risk towns (Vaduz, Balzers, etc.).
3. Output EXCLUDES safe towns (Malbun).
4. Feature count is within a reasonable range.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flood_risk_assessment(traj, env_info, task_info):
    """
    Verify the flood risk analysis result.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    must_include = [t.lower() for t in metadata.get('must_include_towns', ['vaduz', 'balzers', 'schaan'])]
    must_exclude = [t.lower() for t in metadata.get('must_exclude_towns', ['malbun'])]

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Anti-Gaming (20 pts)
    if result.get('file_exists', False):
        if result.get('file_created_during_task', False):
            score += 20
            feedback_parts.append("Output file created successfully")
        else:
            score += 10
            feedback_parts.append("Output file exists but timestamp suggests pre-existence")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (10 pts)
    if result.get('valid_json', False):
        score += 10
    else:
        feedback_parts.append("File is not valid GeoJSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Get extracted town names
    town_names = [n.lower() for n in result.get('town_names', [])]
    feature_count = result.get('feature_count', 0)

    # Criterion 3: Inclusion Accuracy (40 pts)
    # Check if key towns are present
    included_count = 0
    missing_towns = []
    
    for town in must_include:
        if any(town in t for t in town_names):
            included_count += 1
        else:
            missing_towns.append(town)
    
    if len(must_include) > 0:
        inclusion_score = (included_count / len(must_include)) * 40
        score += inclusion_score
        if missing_towns:
            feedback_parts.append(f"Missing expected towns: {', '.join(missing_towns)}")
        else:
            feedback_parts.append("All expected at-risk towns found")

    # Criterion 4: Exclusion Accuracy (30 pts)
    # Check if safe towns are excluded
    excluded_correctly = 0
    found_safe_towns = []
    
    for town in must_exclude:
        if not any(town in t for t in town_names):
            excluded_correctly += 1
        else:
            found_safe_towns.append(town)
            
    if len(must_exclude) > 0:
        exclusion_score = (excluded_correctly / len(must_exclude)) * 30
        score += exclusion_score
        if found_safe_towns:
            feedback_parts.append(f"Incorrectly included safe towns: {', '.join(found_safe_towns)}")
        else:
            feedback_parts.append("Correctly excluded distant towns")

    # Final pass check
    # Must find at least one correct town and exclude the specific mountain town
    passed = (score >= 70) and (included_count >= 1) and (excluded_correctly == len(must_exclude))

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }