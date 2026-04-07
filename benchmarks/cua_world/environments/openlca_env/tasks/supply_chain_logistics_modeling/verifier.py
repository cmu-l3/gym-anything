#!/usr/bin/env python3
"""
Verifier for Supply Chain Logistics Modeling task.

Verifies:
1. Process 'Global Workbench Assembly' exists in the database.
2. Inputs for Wood (~50kg) and Steel (~5kg) exist.
3. Transport Work (t*km) is calculated correctly:
   - Truck: ~17.0 t*km (15 for wood + 2 for steel)
   - Ocean: ~40.0 t*km (40 for steel)
4. Result CSV exists.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_supply_chain_logistics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # 1. Process Existence (20 pts)
    if result.get("process_found", False):
        score += 20
        feedback_parts.append("Process 'Global Workbench Assembly' found.")
    else:
        feedback_parts.append("Process 'Global Workbench Assembly' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Process not found"}

    inputs = result.get("inputs", [])
    
    # Helper to find input by name keywords
    def find_input(keywords, target_amount, tolerance=0.1):
        for item in inputs:
            name = item['name'].lower()
            if any(k.lower() in name for k in keywords):
                # Check amount
                if abs(item['amount'] - target_amount) <= tolerance:
                    return True, item['amount']
        return False, 0

    # 2. Material Inputs (20 pts total)
    # Wood: 50kg
    wood_found, wood_amt = find_input(['wood', 'lumber', 'timber'], 50.0, tolerance=2.0)
    if wood_found:
        score += 10
        feedback_parts.append(f"Wood input correct ({wood_amt}).")
    else:
        feedback_parts.append("Wood input missing or incorrect amount (expected ~50).")

    # Steel: 5kg
    steel_found, steel_amt = find_input(['steel', 'iron'], 5.0, tolerance=0.5)
    if steel_found:
        score += 10
        feedback_parts.append(f"Steel input correct ({steel_amt}).")
    else:
        feedback_parts.append("Steel input missing or incorrect amount (expected ~5).")

    # 3. Transport Calculations (50 pts total)
    # Truck: 17.0 t*km (15 + 2)
    # Allow range 16.0 - 18.0
    truck_found, truck_amt = find_input(['truck', 'lorry', 'road'], 17.0, tolerance=1.5)
    
    # Also check if they just put the distance (300 or 700) - common mistake
    dist_mistake_found, dist_amt = find_input(['truck', 'lorry', 'road'], 300.0, tolerance=50.0)
    
    if truck_found:
        score += 25
        feedback_parts.append(f"Truck transport calculation correct ({truck_amt} t*km).")
    elif dist_mistake_found:
        feedback_parts.append(f"FAILED: Entered distance ({dist_amt} km) instead of transport work (t*km) for Truck.")
    else:
        feedback_parts.append("Truck transport missing or incorrect (expected ~17 t*km).")

    # Ocean: 40.0 t*km
    # Allow range 38.0 - 42.0
    ocean_found, ocean_amt = find_input(['ocean', 'ship', 'water', 'freighter', 'sea'], 40.0, tolerance=2.0)
    
    # Check for distance mistake (8000)
    ocean_dist_mistake, ocean_dist_amt = find_input(['ocean', 'ship', 'water'], 8000.0, tolerance=100.0)

    if ocean_found:
        score += 25
        feedback_parts.append(f"Ocean transport calculation correct ({ocean_amt} t*km).")
    elif ocean_dist_mistake:
        feedback_parts.append(f"FAILED: Entered distance ({ocean_dist_amt} km) instead of transport work (t*km) for Ocean.")
    else:
        feedback_parts.append("Ocean transport missing or incorrect (expected ~40 t*km).")

    # 4. Result CSV (10 pts)
    if result.get("csv_exists", False) and result.get("csv_size", 0) > 10:
        score += 10
        feedback_parts.append("Result CSV exported.")
    else:
        feedback_parts.append("Result CSV missing.")

    passed = score >= 70 and truck_found and ocean_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }