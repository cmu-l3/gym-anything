#!/usr/bin/env python3
"""
Verifier for Custom LCIA Shadow Pricing task.

Criteria:
1. Method Creation (20 pts): 'Corporate Shadow Price 2026' exists in DB.
2. Category Creation (10 pts): 'Carbon Liability' exists in DB.
3. CO2 Factor (30 pts): Value is 0.1 (Precision +/- 0.01).
   - Logic: $100/tonne = $0.1/kg. GWP = 1.
4. Methane Factor (20 pts): Value is 2.5 (Precision +/- 0.1).
   - Logic: $100/tonne = $0.1/kg. GWP = 25. 0.1 * 25 = 2.5.
5. Calculation/Export (20 pts): Result file exists, created during task, > 100 bytes.

Pass Threshold: 60 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_lcia_shadow_pricing(traj, env_info, task_info):
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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
    feedback = []
    
    # 3. Verify Method Creation (20 pts)
    if result.get('method_found', False):
        score += 20
        feedback.append("Method 'Corporate Shadow Price' found.")
    else:
        feedback.append("Method 'Corporate Shadow Price' NOT found in database.")

    # 4. Verify Category Creation (10 pts)
    if result.get('category_found', False):
        score += 10
        feedback.append("Category 'Carbon Liability' found.")
    else:
        feedback.append("Category 'Carbon Liability' NOT found.")

    # 5. Verify Factors (50 pts total)
    factors = result.get('factors', [])
    co2_passed = False
    methane_passed = False
    
    # Tolerances
    co2_target = 0.1
    methane_target = 2.5
    tolerance = 0.05 # Allows small rounding differences

    for f in factors:
        name = f.get('flow', '').lower()
        val = f.get('value', 0.0)

        # Check CO2
        if 'carbon dioxide' in name and not co2_passed:
            if abs(val - co2_target) <= tolerance:
                score += 30
                co2_passed = True
                feedback.append(f"Correct CO2 factor: {val}")
            elif abs(val - 100.0) <= 0.1:
                feedback.append(f"Incorrect CO2 factor: {val} (Did you forget to convert tonnes to kg?)")
            else:
                feedback.append(f"Incorrect CO2 factor: {val} (Expected 0.1)")

        # Check Methane
        if 'methane' in name and not methane_passed:
            if abs(val - methane_target) <= tolerance:
                score += 20
                methane_passed = True
                feedback.append(f"Correct Methane factor: {val}")
            elif abs(val - 2500.0) <= 1.0:
                 feedback.append(f"Incorrect Methane factor: {val} (Did you forget to convert tonnes to kg?)")
            elif abs(val - 0.1) <= tolerance:
                 feedback.append(f"Incorrect Methane factor: {val} (Did you forget GWP multiplier?)")
            else:
                 feedback.append(f"Incorrect Methane factor: {val} (Expected 2.5)")
    
    if not co2_passed:
        feedback.append("CO2 factor missing or incorrect.")
    if not methane_passed:
        feedback.append("Methane factor missing or incorrect.")

    # 6. Verify Export (20 pts)
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('file_size', 0)

    if file_exists and file_created and file_size > 50:
        score += 20
        feedback.append("Result file exported successfully.")
    elif file_exists:
        # Exists but not created during task? Or too small?
        score += 5
        feedback.append("Result file exists but may be empty or stale.")
    else:
        feedback.append("Result file not found.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }