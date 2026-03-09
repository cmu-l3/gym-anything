#!/usr/bin/env python3
"""
Verifier for identify_flood_safe_cities task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_flood_safe_cities(traj, env_info, task_info):
    """
    Verify the agent identified flood-safe cities in South America.
    
    Scoring Breakdown:
    - Buffer Created (20 pts): 'river_buffer_05deg.shp' exists and is Polygon.
    - Result Created (20 pts): 'safe_cities.shp' exists and created during task.
    - Logical Exclusion (20 pts): 'Manaus' (on river) is excluded, 'Paris' (wrong continent) excluded.
    - Logical Inclusion (20 pts): 'Santiago' (safe SA city) is included.
    - Feature Count (20 pts): Count is within reasonable range (not 0, not all cities).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result JSON
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
            
    # 1. Verify Buffer
    if result.get('buffer_exists') and result.get('buffer_created_during_task'):
        if result.get('buffer_geometry') == 'Polygon':
            score += 20
            feedback_parts.append("Buffer layer created successfully")
        else:
            score += 10
            feedback_parts.append("Buffer file exists but geometry type mismatch (expected Polygon)")
    else:
        feedback_parts.append("Buffer layer not created")

    # 2. Verify Result Existence
    if result.get('result_exists') and result.get('result_created_during_task'):
        score += 20
        feedback_parts.append("Result shapefile created")
    else:
        feedback_parts.append("Result shapefile not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Logic (Inclusions/Exclusions)
    included = result.get('included_cities', [])
    excluded_correctly = result.get('excluded_cities_correctly', [])
    
    # Check Santiago (Must be there)
    if "Santiago" in included:
        score += 20
        feedback_parts.append("Santiago included (Correct)")
    else:
        feedback_parts.append("Santiago missing (Incorrect - likely over-filtered)")

    # Check Manaus (Must NOT be there - caught by buffer)
    if "Manaus" in excluded_correctly:
        score += 10
        feedback_parts.append("Manaus excluded (Correct - river buffer worked)")
    else:
        feedback_parts.append("Manaus included (Incorrect - river buffer failed)")
        
    # Check Paris (Must NOT be there - caught by continent)
    if "Paris" in excluded_correctly:
        score += 10
        feedback_parts.append("Paris excluded (Correct - continent filter worked)")
    else:
        feedback_parts.append("Paris included (Incorrect - continent filter failed)")

    # 4. Feature Count Sanity Check
    # Total SA cities > 1M is roughly 40-60. Safe ones should be fewer but > 0.
    count = int(result.get('result_feature_count', 0))
    if 0 < count < 100:
        score += 20
        feedback_parts.append(f"Feature count reasonable ({count})")
    elif count == 0:
        feedback_parts.append("Result file is empty")
    else:
        feedback_parts.append(f"Feature count suspicious ({count})")

    # Final Pass Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }