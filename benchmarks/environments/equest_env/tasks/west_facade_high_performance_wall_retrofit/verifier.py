#!/usr/bin/env python3
"""
Verifier for west_facade_high_performance_wall_retrofit task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

def verify_west_facade_retrofit(traj, env_info, task_info):
    """
    Verifies that the agent created the specific construction and assigned it correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_construction_name', "West Hi-Perf Wall").lower()
    target_u = metadata.get('target_u_value', 0.040)
    tolerance = metadata.get('u_value_tolerance', 0.002)
    west_indicators = metadata.get('west_zone_indicators', ['.W', 'West'])

    # Copy result file
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Construction Creation (30 pts)
    constructions = result.get('constructions', {})
    found_construction = False
    valid_u_value = False
    
    # Check for construction case-insensitive
    target_key = None
    for name, props in constructions.items():
        if name.lower() == target_name:
            found_construction = True
            target_key = name
            u_val = props.get('U-VALUE')
            if u_val is not None and abs(u_val - target_u) <= tolerance:
                valid_u_value = True
            break
            
    if found_construction:
        score += 15
        feedback.append(f"Construction '{target_key}' created.")
        if valid_u_value:
            score += 15
            feedback.append(f"U-Value {u_val} is correct.")
        else:
            feedback.append(f"U-Value incorrect (Expected {target_u}, Got {constructions[target_key].get('U-VALUE')}).")
    else:
        feedback.append(f"Construction '{target_name}' not found.")

    # 2. Verify Assignment (60 pts total)
    walls = result.get('walls', [])
    west_walls_total = 0
    west_walls_correct = 0
    other_walls_total = 0
    other_walls_preserved = 0
    
    for wall in walls:
        parent = wall.get('ParentSpace', '')
        cons = wall.get('Construction', '')
        
        # Determine if West facing based on parent space name
        is_west = any(ind in parent for ind in west_indicators)
        
        # Normalize construction name check
        assigned_target = (cons.lower() == target_name)
        
        if is_west:
            west_walls_total += 1
            if assigned_target:
                west_walls_correct += 1
        else:
            other_walls_total += 1
            if not assigned_target:
                other_walls_preserved += 1
                
    # Score West Assignment (45 pts)
    if west_walls_total > 0:
        west_fraction = west_walls_correct / west_walls_total
        west_score = int(west_fraction * 45)
        score += west_score
        feedback.append(f"Assigned to {west_walls_correct}/{west_walls_total} west walls (+{west_score} pts).")
    else:
        feedback.append("No west walls found in model parsing (parsing error?).")
        
    # Score Preservation (15 pts) - Penalize if they applied it globally
    if other_walls_total > 0:
        other_fraction = other_walls_preserved / other_walls_total
        preservation_score = int(other_fraction * 15)
        score += preservation_score
        if other_walls_preserved < other_walls_total:
             feedback.append(f"Incorrectly assigned to {other_walls_total - other_walls_preserved} non-west walls.")
        else:
             feedback.append("Correctly preserved non-west walls.")

    # 3. Verify Simulation Run (10 pts)
    if result.get('simulation_run', False):
        score += 10
        feedback.append("Simulation ran successfully.")
    else:
        feedback.append("Simulation was not run (check .SIM file timestamp).")

    return {
        "passed": score >= 70 and found_construction and west_walls_correct > 0,
        "score": score,
        "feedback": " | ".join(feedback)
    }