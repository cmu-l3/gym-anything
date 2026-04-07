#!/usr/bin/env python3
"""Verifier for optimize_pv_om_strategy task.

Checks math accuracy, simulation physics constraints, and correct optimization identification.
"""

import json
import tempfile
import os
import math

def verify_optimize_pv_om_strategy(traj, env_info, task_info):
    """Verify PV O&M optimization strategy was completed successfully.
    
    Scoring: 100 points max
    - File exists & created during task: 10
    - Scenario Count (11): 10
    - Physics Consistency (Energy strictly increases): 15
    - Energy Plausibility (50MW -> ~90M kWh): 15
    - Formula Accuracy (downtime, losses, rev, cost): 20
    - Gross Margin Math (Rev - Cost): 15
    - Optimum Correctly Identified: 15
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    energy_min = metadata.get('energy_min', 80000000)
    energy_max = metadata.get('energy_max', 120000000)
    plant_size_kw = metadata.get('plant_size_kw', 50000)
    ppa_price = metadata.get('ppa_price', 0.08)
    lifetime_years = metadata.get('lifetime_years', 25)

    # Load the base task_result metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []
    
    file_exists = result_meta.get('file_exists', False)
    file_modified = result_meta.get('file_modified', False)
    
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File created successfully")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but modified timestamp not verified")
    else:
        return {"passed": False, "score": 0, "feedback": "Output JSON file not found"}

    # Retrieve and parse the actual output file
    target_path = "/home/ga/Documents/SAM_Projects/om_optimization.json"
    temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(target_path, temp_out.name)
        with open(temp_out.name, 'r') as f:
            out_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"File exists but contains invalid JSON: {e}"}
    finally:
        if os.path.exists(temp_out.name):
            os.unlink(temp_out.name)

    # Criterion: Scenario Count (10 pts)
    scenarios = out_data.get('scenarios', [])
    if len(scenarios) == 11:
        score += 10
        feedback_parts.append("11 Scenarios found")
    elif len(scenarios) > 0:
        score += 5
        feedback_parts.append(f"Partial scenarios found ({len(scenarios)})")
    else:
        feedback_parts.append("No scenarios found in output")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Verify scenario rates and sort them
    try:
        scenarios = sorted(scenarios, key=lambda x: x['om_rate'])
    except KeyError:
        return {"passed": False, "score": score, "feedback": "Scenarios missing 'om_rate' key"}

    # Validation Flags
    energy_strictly_increases = True
    formulas_accurate = True
    margin_math_accurate = True
    energy_plausible = True
    
    prev_energy = 0
    calculated_margins = []

    for sc in scenarios:
        om_rate = sc.get('om_rate', 0)
        downtime = sc.get('downtime_pct', -1)
        losses = sc.get('losses_pct', -1)
        energy = sc.get('annual_energy_kwh', 0)
        rev = sc.get('lifetime_revenue', 0)
        cost = sc.get('lifetime_om_cost', 0)
        margin = sc.get('gross_margin', 0)

        # Formula checks
        expected_downtime = 5.0 * (0.8 ** (om_rate - 15))
        expected_losses = 10.0 + expected_downtime
        
        if not math.isclose(downtime, expected_downtime, rel_tol=0.01) or \
           not math.isclose(losses, expected_losses, rel_tol=0.01):
            formulas_accurate = False
            
        expected_rev = energy * ppa_price * lifetime_years
        expected_cost = plant_size_kw * om_rate * lifetime_years
        expected_margin = expected_rev - expected_cost
        
        if not math.isclose(rev, expected_rev, rel_tol=0.01) or \
           not math.isclose(cost, expected_cost, rel_tol=0.01):
            formulas_accurate = False
            
        if not math.isclose(margin, expected_margin, rel_tol=0.01):
            margin_math_accurate = False
            
        if not (energy_min <= energy <= energy_max):
            energy_plausible = False

        if energy <= prev_energy:
            energy_strictly_increases = False
            
        prev_energy = energy
        calculated_margins.append((om_rate, margin))

    # Scoring based on flags
    if energy_strictly_increases:
        score += 15
        feedback_parts.append("Energy strictly increases with O&M")
    else:
        feedback_parts.append("Energy physics failure (does not increase with better O&M)")

    if energy_plausible:
        score += 15
        feedback_parts.append("Energy output physically plausible")
    else:
        feedback_parts.append("Energy output not physically plausible")

    if formulas_accurate:
        score += 20
        feedback_parts.append("Downtime/Revenue/Cost math is perfectly accurate")
    else:
        feedback_parts.append("Formula errors detected in downtime or financials")

    if margin_math_accurate:
        score += 15
        feedback_parts.append("Gross margin calculated correctly")
    else:
        feedback_parts.append("Gross margin math incorrect")

    # Optimum correct
    best_rate_calculated = max(calculated_margins, key=lambda x: x[1])[0]
    reported_best = out_data.get('optimal_om_rate', -1)
    
    if reported_best == best_rate_calculated and formulas_accurate:
        score += 15
        feedback_parts.append(f"Optimal rate correctly identified: {reported_best}")
    else:
        feedback_parts.append(f"Optimal rate incorrect (reported {reported_best}, expected {best_rate_calculated})")

    # Pass threshold 75: Must have at least basic formula accuracy + physics
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }