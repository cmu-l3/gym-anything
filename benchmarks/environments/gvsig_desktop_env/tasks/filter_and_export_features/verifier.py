#!/usr/bin/env python3
"""
Verifier for filter_and_export_features task.

Verifies:
1. Output shapefile components exist (.shp, .shx, .dbf)
2. Output was created during the task (anti-gaming)
3. Feature count matches expected range (10-18)
4. Attributes satisfy the filter condition (POP_EST > 100,000,000)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_filter_and_export_features(traj, env_info, task_info):
    """
    Verify the agent correctly filtered and exported populous countries.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Files Exist (25 pts)
    # ---------------------------------------------------------
    shp = result.get('shp_exists', False)
    shx = result.get('shx_exists', False)
    dbf = result.get('dbf_exists', False)
    
    components = sum([shp, shx, dbf])
    if components == 3:
        score += 25
        feedback_parts.append("Shapefile exported correctly")
    elif components > 0:
        score += components * 5
        feedback_parts.append(f"Incomplete shapefile ({components}/3 components)")
    else:
        return {"passed": False, "score": 0, "feedback": "No output files found"}

    # ---------------------------------------------------------
    # Criterion 2: Anti-Gaming / Validity (15 pts)
    # ---------------------------------------------------------
    created_during = result.get('file_created_during_task', False)
    file_size = result.get('file_size_bytes', 0)
    
    if created_during:
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp predates task")
        
    if file_size > 100: # Non-empty file
        score += 10
    else:
        feedback_parts.append("File appears empty")

    # ---------------------------------------------------------
    # Criterion 3: Feature Count & Attribute Logic (60 pts)
    # ---------------------------------------------------------
    analysis = result.get('dbf_analysis', {})
    count = analysis.get('feature_count', 0)
    valid_count = analysis.get('valid_pop_count', 0)
    min_pop = analysis.get('min_pop', 0)
    
    # Expected range: ~13 features. Allow 10-18.
    if 10 <= count <= 18:
        score += 25
        feedback_parts.append(f"Feature count correct ({count})")
        # Bonus for exact precision
        if 12 <= count <= 14:
            score += 5
    elif 1 <= count < 10:
        score += 10
        feedback_parts.append(f"Feature count too low ({count}), expected ~13")
    elif count > 18:
        # If count is huge (e.g. 177), they likely exported the whole layer without filtering
        if count > 100:
            feedback_parts.append(f"Failed to filter: Exported all {count} features")
        else:
            score += 5
            feedback_parts.append(f"Feature count too high ({count})")
    
    # Check if attributes satisfy logic
    if valid_count > 0:
        if valid_count == count:
            score += 30
            feedback_parts.append("All features satisfy POP_EST > 100M")
        elif valid_count >= count * 0.8:
            score += 20
            feedback_parts.append("Most features satisfy filter")
        else:
            score += 5
            feedback_parts.append("Some features satisfy filter, but many invalid")
    else:
        if count > 0:
            feedback_parts.append("No exported features meet the population criteria")

    # ---------------------------------------------------------
    # Final Calculation
    # ---------------------------------------------------------
    passed = score >= 60 and count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }