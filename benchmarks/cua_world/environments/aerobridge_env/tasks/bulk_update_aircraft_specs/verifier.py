#!/usr/bin/env python3
"""
Verifier for bulk_update_aircraft_specs task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_update_aircraft_specs(traj, env_info, task_info):
    """
    Verifies that the aircraft mass fields were updated correctly.
    
    Criteria:
    1. Script created (10 pts)
    2. Targets updated to correct KG value (not Grams) (50 pts)
    3. Distractor aircraft NOT modified (20 pts)
    4. Database actually modified (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    distractor = metadata.get('distractor', {})

    db_state = result.get('db_state', {})
    
    # --- Check 1: Script Creation (10 pts) ---
    if result.get('script_created'):
        score += 10
        feedback_parts.append("Script file created.")
    else:
        feedback_parts.append("No Python script found.")

    # --- Check 2: Targets Updated (50 pts) ---
    # Split points: 20 for updating at all, 30 for correct unit conversion
    updates_attempted = 0
    units_correct = 0
    total_targets = len(targets)
    
    for t in targets:
        name = t['model']
        expected_kg = t['expected_kg']
        grams = t['grams']
        
        actual = db_state.get(name, {}).get('mass', 0.0)
        
        if actual == 0.0:
            feedback_parts.append(f"❌ {name} mass is still 0.")
            continue
            
        updates_attempted += 1
        
        # Check tolerance (float issues)
        if abs(actual - expected_kg) < 0.01:
            units_correct += 1
            feedback_parts.append(f"✅ {name} updated correctly ({actual} kg).")
        elif abs(actual - grams) < 1.0:
            feedback_parts.append(f"⚠️ {name} updated but looks like GRAMS ({actual}). Forgot conversion?")
        else:
            feedback_parts.append(f"❌ {name} updated to incorrect value ({actual}). Expected {expected_kg}.")

    if updates_attempted > 0:
        score += 20 * (updates_attempted / total_targets)
    
    if units_correct > 0:
        score += 30 * (units_correct / total_targets)

    # --- Check 3: Distractor Safety (20 pts) ---
    dist_name = distractor.get('model', 'Custom Heavy Lifter')
    dist_initial = distractor.get('initial_kg', 25.5)
    dist_actual = db_state.get(dist_name, {}).get('mass', 0.0)
    
    if abs(dist_actual - dist_initial) < 0.01:
        score += 20
        feedback_parts.append(f"✅ Distractor '{dist_name}' preserved.")
    else:
        feedback_parts.append(f"❌ Distractor '{dist_name}' was modified! (Changed from {dist_initial} to {dist_actual})")

    # --- Check 4: General DB Modification (20 pts) ---
    # If any updates happened, we give these points
    if updates_attempted > 0:
        score += 20
    
    # Final Tally
    score = min(100, round(score))
    
    # Pass if score >= 80 (Meaning units MUST be correct)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }