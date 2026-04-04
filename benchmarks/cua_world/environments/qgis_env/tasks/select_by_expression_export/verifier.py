#!/usr/bin/env python3
"""
Verifier for select_by_expression_export task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_by_expression_export(traj, env_info, task_info):
    """
    Verify that the user correctly selected features with pop_max > 10M and exported them.
    
    Scoring Criteria:
    1. Output file exists (10 pts)
    2. Output is valid GeoJSON (10 pts)
    3. File created during task (Anti-gaming) (10 pts)
    4. Feature count is reasonable (10-50 for >10M query) (20 pts)
    5. All exported features have pop_max > 10M (No incorrect features) (30 pts)
    6. Contains known mega-cities (Tokyo, Delhi, etc.) (20 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Analysis result: {result}")
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Exists (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid GeoJSON (10 pts)
    if result.get("valid_geojson"):
        score += 10
        feedback_parts.append("Valid GeoJSON")
    else:
        feedback_parts.append("Invalid or unreadable GeoJSON")
        # Fail early if invalid
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 3: Created during task (10 pts)
    if result.get("is_new_file"):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task start (Anti-gaming)")
        
    # Criterion 4: Feature Count (20 pts)
    # Natural Earth 1:110m usually has ~20-30 cities > 10M. 
    # Broad range 5-100 to account for potential data version differences.
    count = result.get("feature_count", 0)
    if 5 <= count <= 100:
        score += 20
        feedback_parts.append(f"Feature count reasonable ({count})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Feature count suspicious ({count})")
    else:
        feedback_parts.append("File is empty")
        
    # Criterion 5: Attribute Correctness (30 pts)
    # CRITICAL: No features <= 10M should be present
    incorrect = result.get("incorrect_features", 0)
    all_correct = result.get("all_correct_threshold", False)
    
    if all_correct and count > 0:
        score += 30
        feedback_parts.append("All features meet population criteria")
    elif count > 0:
        # Penalize for incorrect features
        feedback_parts.append(f"Found {incorrect} features with population <= 10M")
        if incorrect < (count * 0.5): # Partial credit if mostly correct
            score += 10
            
    # Criterion 6: Content Verification (Known Cities) (20 pts)
    known_found = len(result.get("known_cities_found", []))
    if known_found >= 3:
        score += 20
        feedback_parts.append(f"Confirmed known mega-cities ({known_found} found)")
    elif known_found > 0:
        score += 10
        feedback_parts.append(f"Few known cities found ({known_found})")
    else:
        feedback_parts.append("No expected mega-cities found in output")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }