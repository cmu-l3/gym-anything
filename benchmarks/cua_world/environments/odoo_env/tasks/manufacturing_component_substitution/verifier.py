#!/usr/bin/env python3
"""
Verifier for manufacturing_component_substitution task.

Checks:
1. Manufacturing Order exists and is Done.
2. The MO consumed 'Premium Gasket G-200'.
3. The MO did NOT consume 'Standard Gasket G-100'.
4. The Master BOM was NOT modified (still contains Standard Gasket).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_manufacturing_component_substitution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mrp_sub_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []

    mo_found = result.get('mo_found', False)
    mo_data = result.get('mo_data', {})
    bom_products = result.get('bom_product_ids', [])
    targets = result.get('target_ids', {})

    std_id = targets.get('standard_gasket')
    prem_id = targets.get('premium_gasket')

    # Criterion 1: MO Created and Done (20 pts)
    if mo_found and mo_data.get('state') == 'done':
        score += 20
        feedback.append("Manufacturing Order created and completed (20/20)")
    elif mo_found:
        score += 10
        feedback.append(f"Manufacturing Order created but state is '{mo_data.get('state')}' (expected 'done') (10/20)")
    else:
        feedback.append("No Manufacturing Order found (0/20)")

    # Criterion 2: Substitute Component Consumed (40 pts)
    consumed = mo_data.get('consumed_product_ids', [])
    if prem_id in consumed:
        score += 40
        feedback.append("Premium Gasket G-200 was successfully substituted and consumed (40/40)")
    else:
        feedback.append("Premium Gasket G-200 was NOT found in the consumed items (0/40)")

    # Criterion 3: Original Component Not Consumed (20 pts)
    if std_id not in consumed:
        score += 20
        feedback.append("Standard Gasket G-100 was correctly excluded from consumption (20/20)")
    else:
        feedback.append("Standard Gasket G-100 was consumed despite being out of stock (did you delete the line?) (0/20)")

    # Criterion 4: Master BOM Unchanged (20 pts)
    # The BOM should still have Standard (std_id) and NOT Premium (prem_id)
    bom_ok = (std_id in bom_products) and (prem_id not in bom_products)
    if bom_ok:
        score += 20
        feedback.append("Master Bill of Materials remains unchanged (20/20)")
    else:
        feedback.append("Master Bill of Materials was modified incorrectly (should be a one-time MO change) (0/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }