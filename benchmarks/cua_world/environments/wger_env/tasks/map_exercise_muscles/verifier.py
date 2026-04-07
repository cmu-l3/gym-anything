#!/usr/bin/env python3
"""
Verifier for map_exercise_muscles task in wger.

Checks:
1. Exercise still exists (not accidentally deleted)
2. Identity Preservation: Target exercise ID remains identical (prevents 'delete and recreate' game)
3. Primary Muscle accurately matches expected relation ("Quadriceps femoris")
4. Secondary Muscle accurately matches expected relation ("Gluteus maximus")
5. Precision test (agent didn't just 'select all' to bypass logic)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_exercise_muscles(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_primary = metadata.get('expected_primary', 'Quadriceps femoris')
    expected_secondary = metadata.get('expected_secondary', 'Gluteus maximus')

    # Copy result JSON from container securely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_result = result.get('db_result', {})
    initial_id = str(result.get('initial_id', '-1')).strip()
    
    score = 0
    feedback_parts = []

    # Criterion 1: Exercise Exists in DB (10 pts)
    exists = db_result.get('exists', False)
    if not exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Exercise 'Landmine Reverse Lunge' could not be found in the database. It may have been renamed or deleted."
        }
    
    score += 10
    feedback_parts.append("✅ Exercise exists")

    # Criterion 2: ID Match / Identity Preservation (10 pts)
    # Prevents deleting the original exercise and creating a brand new one with muscles selected
    current_id = str(db_result.get('id', '-2')).strip()
    if current_id == initial_id:
        score += 10
        feedback_parts.append("✅ Original exercise preserved (not recreated)")
    else:
        feedback_parts.append(f"❌ Exercise ID changed (original: {initial_id}, new: {current_id}) - Points deducted for deletion/recreation")

    # Prepare data for testing
    primary_muscles = db_result.get('primary', [])
    secondary_muscles = db_result.get('secondary', [])
    
    primary_lower = [m.lower() for m in primary_muscles]
    secondary_lower = [m.lower() for m in secondary_muscles]

    # Criterion 3: Correct Primary Muscle (30 pts)
    if expected_primary.lower() in primary_lower:
        score += 30
        feedback_parts.append(f"✅ Primary muscle '{expected_primary}' correctly assigned")
    else:
        feedback_parts.append(f"❌ Missing primary muscle '{expected_primary}'")

    # Criterion 4: Correct Secondary Muscle (30 pts)
    if expected_secondary.lower() in secondary_lower:
        score += 30
        feedback_parts.append(f"✅ Secondary muscle '{expected_secondary}' correctly assigned")
    else:
        feedback_parts.append(f"❌ Missing secondary muscle '{expected_secondary}'")

    # Criterion 5: Precision (20 pts total: 10 pts primary, 10 pts secondary)
    # Prevents agent gaming by simply selecting every muscle on the page
    precision_points = 0
    if len(primary_muscles) == 1 and expected_primary.lower() in primary_lower:
        precision_points += 10
        
    if len(secondary_muscles) == 1 and expected_secondary.lower() in secondary_lower:
        precision_points += 10

    if precision_points > 0:
        score += precision_points
        if precision_points == 20:
            feedback_parts.append("✅ Precision perfect: Only required muscles were assigned")
        else:
            feedback_parts.append(f"⚠️ Precision partial (+{precision_points}): Some extra muscles may be assigned")
    elif len(primary_muscles) > 1 or len(secondary_muscles) > 1:
        feedback_parts.append(f"❌ Extra muscles detected (Primary count: {len(primary_muscles)}, Secondary count: {len(secondary_muscles)})")

    # Evaluate final passage (Requires at least correct assignments even if minor precision slips happen)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }