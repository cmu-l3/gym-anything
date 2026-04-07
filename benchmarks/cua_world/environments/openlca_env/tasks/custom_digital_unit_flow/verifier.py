#!/usr/bin/env python3
"""
Verifier for Custom Digital Unit Flow task.

Verifies:
1. "Digital Units" Unit Group exists.
2. "Terabyte" and "Gigabyte" units exist with correct 1000x ratio.
3. "Data Amount" Flow Property exists and uses the unit group.
4. "Cloud Data Service" Flow exists and uses the flow property.
5. "Data Center Operation" Process exists and outputs 1.0 of the flow.

Scoring:
- 20 pts: Unit Group creation
- 20 pts: Units definition & conversion correctness
- 20 pts: Flow Property creation & linking
- 20 pts: Flow creation & linking
- 20 pts: Process creation & correct amount
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_digital_unit_flow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # 1. Verify Unit Group (20 pts)
    if result.get("unit_group_found"):
        score += 20
        feedback.append("Unit Group 'Digital Units' created.")
    else:
        feedback.append("Unit Group 'Digital Units' NOT found.")
    
    # 2. Verify Units and Conversion (20 pts)
    units = result.get("units", [])
    tb_unit = next((u for u in units if "terabyte" in u["name"].lower()), None)
    gb_unit = next((u for u in units if "gigabyte" in u["name"].lower()), None)
    
    units_ok = False
    conversion_ok = False
    
    if tb_unit and gb_unit:
        units_ok = True
        # Check conversion factor
        # It depends on which is reference. 
        # If TB is ref (1.0), GB should be 0.001
        # If GB is ref (1.0), TB should be 1000.0
        # If neither is ref (unlikely default), ratio should still be 1000
        
        factor_tb = tb_unit["factor"]
        factor_gb = gb_unit["factor"]
        
        # Calculate ratio: TB / GB should be 1000
        if factor_gb > 0:
            ratio = factor_tb / factor_gb
            # Allow small float error
            if math.isclose(ratio, 1000.0, rel_tol=1e-5):
                conversion_ok = True
            elif math.isclose(ratio, 0.001, rel_tol=1e-5):
                 # They might have inverted logic? 1 TB = 1000 GB, so 1 TB is larger.
                 # If TB factor is 1, GB factor is 0.001 (relative to TB ref).
                 # If GB factor is 1, TB factor is 1000 (relative to GB ref).
                 # Ratio factor_tb / factor_gb should be 1000.
                 feedback.append(f"Conversion logic inverted or incorrect (Ratio: {ratio}).")
            else:
                 feedback.append(f"Incorrect conversion factor ratio: {ratio}")
        else:
            feedback.append("Gigabyte factor is 0 or invalid.")
    else:
        feedback.append(f"Units missing. Found: {[u['name'] for u in units]}")

    if units_ok:
        score += 10
        feedback.append("Units Terabyte/Gigabyte found.")
    if conversion_ok:
        score += 10
        feedback.append("Conversion factor correct (1 TB = 1000 GB).")

    # 3. Verify Flow Property (20 pts)
    fp = result.get("flow_property", {})
    if fp.get("found"):
        score += 10
        feedback.append("Flow Property 'Data Amount' created.")
        if fp.get("linked_to_unit_group"):
            score += 10
            feedback.append("Flow Property linked to correct Unit Group.")
        else:
            feedback.append("Flow Property linked to WRONG Unit Group.")
    else:
        feedback.append("Flow Property 'Data Amount' NOT found.")

    # 4. Verify Flow (20 pts)
    flow = result.get("flow", {})
    if flow.get("found"):
        score += 10
        feedback.append("Flow 'Cloud Data Service' created.")
        if flow.get("linked_to_property"):
            score += 10
            feedback.append("Flow linked to correct Flow Property.")
        else:
            feedback.append("Flow linked to WRONG Flow Property.")
    else:
        feedback.append("Flow 'Cloud Data Service' NOT found.")

    # 5. Verify Process (20 pts)
    proc = result.get("process", {})
    if proc.get("found"):
        score += 10
        feedback.append("Process 'Data Center Operation' found using flow.")
        amount = proc.get("amount", 0)
        if math.isclose(amount, 1.0, rel_tol=1e-5):
            score += 10
            feedback.append("Process output amount correct (1.0).")
        else:
            feedback.append(f"Process output amount incorrect: {amount} (expected 1.0).")
    else:
        feedback.append("Process 'Data Center Operation' using the flow NOT found.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }