#!/usr/bin/env python3
"""
Verifier for Chemical Reaction Stoichiometry Task.

Verifies:
1. Process creation ("Stoichiometric Methane Combustion")
2. Methane Input (1.0 kg)
3. Oxygen Input (~4.0 kg)
4. CO2 Output (~2.75 kg)
5. Water Output (~2.25 kg)
6. Mass balance (Total Input ≈ Total Output)

Scoring:
- Process exists: 20 pts
- Methane correct: 20 pts
- Oxygen correct: 20 pts
- CO2 correct: 20 pts
- Water correct: 20 pts
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stoichiometry(traj, env_info, task_info):
    """
    Verify the OpenLCA stoichiometry task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "methane_input": 1.0,
        "oxygen_input": 4.0,
        "co2_output": 2.75,
        "water_output": 2.25
    })
    tolerance = metadata.get('tolerance', 0.1)

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

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # 1. Check Process Existence
    if not result.get('process_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Process 'Stoichiometric Methane Combustion' not found in database."
        }
    
    score += 20
    feedback_parts.append("Process found (20/20)")

    # 2. Analyze Exchanges
    exchanges = result.get('exchanges', [])
    
    found_methane = False
    found_oxygen = False
    found_co2 = False
    found_water = False
    
    total_input_mass = 0.0
    total_output_mass = 0.0

    for ex in exchanges:
        name = ex.get('name', '').lower()
        amount = ex.get('amount', 0.0)
        is_input = ex.get('is_input', False)

        # Accumulate mass for balance check
        if is_input:
            total_input_mass += amount
        else:
            total_output_mass += amount

        # Check Methane (Input)
        if 'methane' in name and is_input:
            if math.isclose(amount, expected['methane_input'], abs_tol=tolerance):
                found_methane = True
        
        # Check Oxygen (Input)
        elif 'oxygen' in name and is_input:
            if math.isclose(amount, expected['oxygen_input'], abs_tol=tolerance):
                found_oxygen = True
        
        # Check CO2 (Output)
        elif ('carbon dioxide' in name or 'co2' in name) and not is_input:
            if math.isclose(amount, expected['co2_output'], abs_tol=tolerance):
                found_co2 = True
        
        # Check Water (Output)
        elif 'water' in name and not is_input:
            # Be careful not to match "Water (fresh)" input if user picked wrong flow
            # But task said create outputs.
            if math.isclose(amount, expected['water_output'], abs_tol=tolerance):
                found_water = True

    # Scoring individual components
    if found_methane:
        score += 20
        feedback_parts.append("Methane Input OK (20/20)")
    else:
        feedback_parts.append(f"Methane Input incorrect/missing (Expected {expected['methane_input']})")

    if found_oxygen:
        score += 20
        feedback_parts.append("Oxygen Input OK (20/20)")
    else:
        feedback_parts.append(f"Oxygen Input incorrect/missing (Expected ~{expected['oxygen_input']})")

    if found_co2:
        score += 20
        feedback_parts.append("CO2 Output OK (20/20)")
    else:
        feedback_parts.append(f"CO2 Output incorrect/missing (Expected ~{expected['co2_output']})")

    if found_water:
        score += 20
        feedback_parts.append("Water Output OK (20/20)")
    else:
        feedback_parts.append(f"Water Output incorrect/missing (Expected ~{expected['water_output']})")

    # Mass Balance Check (Bonus/Validation info)
    mass_diff = abs(total_input_mass - total_output_mass)
    if mass_diff < tolerance:
        feedback_parts.append(f"Mass Balanced (Diff: {mass_diff:.4f})")
    else:
        feedback_parts.append(f"Mass Imbalance (In: {total_input_mass:.2f}, Out: {total_output_mass:.2f})")

    # VLM Check (Optional but good for anti-gaming - ensuring they used the UI)
    # We could check if trajectory shows the process editor. 
    # For now, the programmatic check is very strong (specific values in DB).

    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }