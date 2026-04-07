#!/usr/bin/env python3
"""
Verifier for compare_east_west_vs_south_rooftop_pv task.
Uses programmatic verification, checking math calculations and plausible bounds for the PySAM simulation outputs.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def try_float(value, default=0.0):
    try:
        return float(value)
    except (ValueError, TypeError):
        return default

def _independent_file_check(copy_from_env):
    """Copy the agent's actual output file and independently verify its contents."""
    path = "/home/ga/Documents/SAM_Projects/rooftop_layout_comparison.json"
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(path, temp.name)
        with open(temp.name, 'r') as f:
            raw = json.load(f)
            
        details = {'raw_file_found': True}
        details['keys'] = list(raw.keys())
        return True, details
    except Exception:
        return False, {'raw_file_found': False}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

def verify_layout_comparison(traj, env_info, task_info):
    """
    Verify the PV layout comparison was correctly executed.
    
    Scoring System:
    - File Exists & created during task: 10
    - Capacity A calculation correct: 15
    - Capacity B calculation correct: 15
    - Energy A simulation plausible: 20
    - Energy B simulation plausible: 20
    - Winning strategy correctly identified: 20
    
    Total: 100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cap_A = metadata.get('expected_capacity_A', 1300)
    expected_cap_B = metadata.get('expected_capacity_B', 1900)
    expected_energy_A_min = metadata.get('expected_energy_A_min', 1900000)
    expected_energy_A_max = metadata.get('expected_energy_A_max', 2800000)
    expected_energy_B_min = metadata.get('expected_energy_B_min', 2500000)
    expected_energy_B_max = metadata.get('expected_energy_B_max', 3800000)
    expected_winner = metadata.get('expected_winning_strategy', 'B')

    # Read exported JSON
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

    score = 0
    feedback_parts = []
    
    # Check 1: Output File Exists and was modified
    file_exists = result.get('file_exists') in [True, 'true', 'True']
    file_modified = result.get('file_modified') in [True, 'true', 'True']
    
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File exists and was modified")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but timestamp indicates it wasn't modified during task")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Verify python was executed (Anti-gaming)
    python_ran = result.get('python_ran') in [True, 'true', 'True']
    if not python_ran:
        feedback_parts.append("WARNING: PySAM simulation scripts were not detected. Might be hardcoded.")

    # Parse exported variables
    cap_a = try_float(result.get('cap_a'))
    cap_b = try_float(result.get('cap_b'))
    en_a = try_float(result.get('en_a'))
    en_b = try_float(result.get('en_b'))
    winner = str(result.get('winner', '')).strip().upper()

    # Check 2: Capacity A
    if abs(cap_a - expected_cap_A) < 1.0:
        score += 15
        feedback_parts.append(f"Capacity A correct ({cap_a} kW)")
    else:
        feedback_parts.append(f"Capacity A incorrect (Expected {expected_cap_A}, Got {cap_a})")

    # Check 3: Capacity B
    if abs(cap_b - expected_cap_B) < 1.0:
        score += 15
        feedback_parts.append(f"Capacity B correct ({cap_b} kW)")
    else:
        feedback_parts.append(f"Capacity B incorrect (Expected {expected_cap_B}, Got {cap_b})")

    # Check 4: Energy A Simulation Bounds
    if expected_energy_A_min <= en_a <= expected_energy_A_max:
        score += 20
        feedback_parts.append(f"Energy A within expected plausible bounds ({en_a} kWh)")
    else:
        feedback_parts.append(f"Energy A bounds check failed ({en_a} kWh)")

    # Check 5: Energy B Simulation Bounds
    if expected_energy_B_min <= en_b <= expected_energy_B_max:
        score += 20
        feedback_parts.append(f"Energy B within expected plausible bounds ({en_b} kWh)")
    else:
        feedback_parts.append(f"Energy B bounds check failed ({en_b} kWh)")

    # Check 6: Winning Strategy
    # Sometimes it returns "B" or "Strategy B", etc.
    if expected_winner in winner or winner == 'STRATEGY B':
        score += 20
        feedback_parts.append("Correct winning strategy identified")
    else:
        feedback_parts.append(f"Incorrect winning strategy identified ({winner})")

    # Independent file check
    ind_ok, ind_details = _independent_file_check(copy_from_env)
    if not ind_ok:
        feedback_parts.append("Independent file cross-check failed (file might be malformed or missing)")

    passed = score >= 70 and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }