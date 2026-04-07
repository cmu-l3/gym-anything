#!/usr/bin/env python3
"""Verifier for optimize_gcr_land_cost_tradeoff task.

Validates that the agent computed the LCOE tradeoff correctly by running
the PySAM Pvwattsv8 simulation and correctly translating physical outcomes
into financial calculations.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_expected_values(gcr, annual_energy_kwh, metadata):
    """Calculate the expected geometric and financial outcomes for a given GCR and energy."""
    module_area_m2 = metadata.get('module_area_m2', 333333.33)
    acres_per_m2 = metadata.get('acres_per_m2', 4046.86)
    land_cost_per_acre = metadata.get('land_cost_per_acre', 60000)
    base_cap_cost = metadata.get('base_cap_cost', 50000000)
    annual_om_cost = metadata.get('annual_om_cost', 750000)
    fcr = metadata.get('fcr', 0.08)

    land_area_m2 = module_area_m2 / gcr
    land_area_acres = land_area_m2 / acres_per_m2
    land_cost = land_cost_per_acre * land_area_acres
    total_cap_cost = base_cap_cost + land_cost
    annualized_cost = (total_cap_cost * fcr) + annual_om_cost
    lcoe_cents_per_kwh = (annualized_cost / annual_energy_kwh) * 100

    return {
        'land_area_acres': land_area_acres,
        'lcoe_cents_per_kwh': lcoe_cents_per_kwh
    }


def verify_optimize_gcr(traj, env_info, task_info):
    """Verify GCR optimization task logic and math.

    Scoring: 100 points max
    - File exists & created during task: 10
    - Python script executed: 10
    - Has 5 requested GCRs in JSON structure: 15
    - Physics Trend (Energy decreases as GCR increases): 25
    - Geometry calculations correct: 15
    - Financial LCOE calculations correct: 15
    - Optima correctly identified: 10
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SAM_Projects/gcr_optimization.json')

    # 1. Read the framework's export metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task export status: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    file_exists = str(export_result.get('file_exists', '')).lower() == 'true'
    file_modified = str(export_result.get('file_modified', '')).lower() == 'true'
    python_ran = str(export_result.get('python_ran', '')).lower() == 'true'

    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File created correctly")
    elif file_exists:
        feedback_parts.append("File exists but old/unmodified")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file was not created"}

    if python_ran:
        score += 10
        feedback_parts.append("Python automation used")
    else:
        feedback_parts.append("No Python/PySAM execution detected")

    # 2. Read the actual output JSON file produced by the agent
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(expected_output_path, temp_output.name)
        with open(temp_output.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse agent JSON output: {e}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    results = agent_data.get('results', [])
    
    if not isinstance(results, list) or len(results) == 0:
        return {"passed": False, "score": score, "feedback": "Missing or empty 'results' array in JSON"}

    # Sort results by GCR to check trends easily
    try:
        results = sorted(results, key=lambda x: float(x.get('gcr', 0)))
    except (ValueError, TypeError):
        return {"passed": False, "score": score, "feedback": "Invalid 'gcr' values in results"}

    # Evaluate Data Completeness (15 pts)
    extracted_gcrs = [float(r.get('gcr', 0)) for r in results]
    required_gcrs = metadata.get('required_gcrs', [0.3, 0.4, 0.5, 0.6, 0.7])
    
    gcr_matches = sum(1 for g in required_gcrs if any(math.isclose(g, eg, abs_tol=0.01) for eg in extracted_gcrs))
    if gcr_matches == len(required_gcrs):
        score += 15
        feedback_parts.append("All requested GCRs present")
    else:
        score += int((gcr_matches / len(required_gcrs)) * 15)
        feedback_parts.append(f"Found {gcr_matches}/{len(required_gcrs)} requested GCRs")

    # Evaluate Physics Accuracy (25 pts)
    # Energy must monotonically decrease as GCR increases due to self-shading/backtracking
    energies = [float(r.get('annual_energy_kwh', 0)) for r in results]
    if len(energies) > 1 and all(e > 0 for e in energies):
        is_strictly_decreasing = all(energies[i] > energies[i+1] for i in range(len(energies)-1))
        plausible_range = all(80_000_000 <= e <= 140_000_000 for e in energies)  # 50MW in Phoenix ~ 100-115 GWh

        if is_strictly_decreasing and plausible_range:
            score += 25
            feedback_parts.append("Energy physics trend correct")
        elif is_strictly_decreasing:
            score += 15
            feedback_parts.append("Energy trend correct but values outside plausible range")
        else:
            feedback_parts.append("Energy values did not properly decrease as GCR increased (failed physics check)")
    else:
        feedback_parts.append("Missing or invalid energy values")

    # Evaluate Geometry and Financial accuracy (15 pts each)
    geom_correct = 0
    fin_correct = 0
    
    lowest_lcoe = float('inf')
    calculated_best_gcr = None

    for r in results:
        g = float(r.get('gcr', 0.1))
        e = float(r.get('annual_energy_kwh', 1))
        agent_acres = float(r.get('land_area_acres', -1))
        agent_lcoe = float(r.get('lcoe_cents_per_kwh', -1))
        
        expected = calculate_expected_values(g, e, metadata)
        
        # Track our calculation of the best GCR based on the agent's reported energies
        if expected['lcoe_cents_per_kwh'] < lowest_lcoe:
            lowest_lcoe = expected['lcoe_cents_per_kwh']
            calculated_best_gcr = g

        if math.isclose(agent_acres, expected['land_area_acres'], rel_tol=0.02):
            geom_correct += 1
            
        if math.isclose(agent_lcoe, expected['lcoe_cents_per_kwh'], rel_tol=0.02):
            fin_correct += 1

    if len(results) > 0:
        score += int((geom_correct / len(results)) * 15)
        score += int((fin_correct / len(results)) * 15)
        
    if geom_correct == len(results) and len(results) > 0:
        feedback_parts.append("Geometry math correct")
    if fin_correct == len(results) and len(results) > 0:
        feedback_parts.append("Financial math correct")

    # Evaluate Optimal Identification (10 pts)
    agent_optimal = agent_data.get('optimal_gcr')
    if agent_optimal is not None and calculated_best_gcr is not None:
        try:
            if math.isclose(float(agent_optimal), calculated_best_gcr, abs_tol=0.01):
                score += 10
                feedback_parts.append("Optimum correctly identified")
            else:
                feedback_parts.append(f"Optimum misidentified (Expected {calculated_best_gcr}, got {agent_optimal})")
        except (ValueError, TypeError):
            feedback_parts.append("Invalid optimal_gcr format")
    else:
        feedback_parts.append("Missing optimal_gcr")

    # Final pass logic
    passed = score >= 75 and file_exists and file_modified and (geom_correct > 0 and fin_correct > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }