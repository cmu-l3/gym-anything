#!/usr/bin/env python3
"""
Verifier for Population Projection Update task.

Scoring (100 points total):
- 40 pts: Population 2024 value matches expected projection (+/- 1)
- 30 pts: Population under 1 year 2024 value matches expected projection (+/- 1)
- 20 pts: Dataset marked as Complete
- 10 pts: Data entered (partial credit if values exist but calculation is wrong)

Formula: Value_2024 = Value_2022 * 1.025 * 1.025 (Rounded)
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

def calculate_projection(baseline, years=2, rate=0.025):
    """Calculate compound growth projection."""
    try:
        val = float(baseline)
        projected = val * ((1 + rate) ** years)
        # Round half up logic or standard round
        return round(projected)
    except (ValueError, TypeError):
        return 0

def verify_population_projection_update(traj, env_info, task_info):
    """Verify population projection calculations and entry."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/population_projection_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    baseline_pop = result.get('baseline_2022', {}).get('population', '0')
    baseline_u1 = result.get('baseline_2022', {}).get('population_under_1', '0')
    
    entered_pop = result.get('entered_2024', {}).get('population', '0')
    entered_u1 = result.get('entered_2024', {}).get('population_under_1', '0')
    
    is_complete = result.get('is_dataset_complete', False)

    # Calculate expectations
    expected_pop = calculate_projection(baseline_pop)
    expected_u1 = calculate_projection(baseline_u1)
    
    # Parse entered values
    try:
        entered_pop_val = float(entered_pop)
        entered_u1_val = float(entered_u1)
    except ValueError:
        entered_pop_val = 0
        entered_u1_val = 0

    # 1. Partial Credit for Entry (10 pts)
    if entered_pop_val > 0 or entered_u1_val > 0:
        score += 10
        feedback_parts.append("Data entry attempted (+10)")
    else:
        feedback_parts.append("No data entered")

    # 2. Check Population Calculation (40 pts)
    # Tolerance +/- 1 for rounding differences
    if abs(entered_pop_val - expected_pop) <= 1 and expected_pop > 0:
        score += 40
        feedback_parts.append(f"Population projection correct (Entered: {int(entered_pop_val)}, Expected: {expected_pop}) (+40)")
    elif expected_pop > 0:
        feedback_parts.append(f"Population projection incorrect (Entered: {int(entered_pop_val)}, Expected: {expected_pop})")
        
    # 3. Check Population U1 Calculation (30 pts)
    if abs(entered_u1_val - expected_u1) <= 1 and expected_u1 > 0:
        score += 30
        feedback_parts.append(f"Pop <1 projection correct (Entered: {int(entered_u1_val)}, Expected: {expected_u1}) (+30)")
    elif expected_u1 > 0:
        feedback_parts.append(f"Pop <1 projection incorrect (Entered: {int(entered_u1_val)}, Expected: {expected_u1})")

    # 4. Check Completion (20 pts)
    if is_complete:
        score += 20
        feedback_parts.append("Dataset marked Complete (+20)")
    else:
        feedback_parts.append("Dataset NOT marked Complete")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }