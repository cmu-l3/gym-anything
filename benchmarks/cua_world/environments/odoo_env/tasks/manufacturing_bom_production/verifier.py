#!/usr/bin/env python3
"""
Verifier for manufacturing_bom_production task.

Scoring (100 points):
- 10 pts: Bill of Materials exists for 'Smart Home Hub Pro'
- 10 pts: BoM has exactly 6 component lines
- 30 pts: Component quantities are correct (5 pts per component)
- 10 pts: Manufacturing Order exists for 12 units
- 10 pts: Manufacturing Order is Confirmed (not draft)
- 30 pts: Manufacturing Order is Done

Pass threshold: 65 points
"""

import json
import logging
import tempfile
import os

logger = logging.getLogger(__name__)

def verify_manufacturing_bom_production(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    score = 0
    feedback = []

    # 1. Verify BoM Existence (10 pts)
    if result.get('bom_found'):
        score += 10
        feedback.append("Bill of Materials created.")
    else:
        feedback.append("No Bill of Materials found for the product.")

    # 2. Verify BoM Structure (10 pts + 30 pts)
    bom_lines = result.get('bom_lines', [])
    setup_expected = result.get('setup_expected', [])
    setup_components = result.get('setup_components', {}) # name -> id map

    # Check line count
    if len(bom_lines) == 6:
        score += 10
        feedback.append("BoM has correct number of components (6).")
    else:
        feedback.append(f"BoM has {len(bom_lines)} components (expected 6).")

    # Check quantities (5 pts each)
    # We map existing bom lines by product ID or Name
    bom_map = {} # id -> qty
    bom_name_map = {} # name -> qty (fallback)
    
    for line in bom_lines:
        bom_map[line['product_id']] = line['qty']
        bom_name_map[line['product_name']] = line['qty']

    qty_score = 0
    for exp in setup_expected:
        name = exp['name']
        needed = exp['qty_needed']
        
        # Try finding by ID first
        pid = setup_components.get(name)
        
        found_qty = 0
        if pid in bom_map:
            found_qty = bom_map[pid]
        elif name in bom_name_map:
            found_qty = bom_name_map[name]
            
        if abs(found_qty - needed) < 0.01:
            qty_score += 5
        else:
            feedback.append(f"Incorrect qty for {name}: found {found_qty}, expected {needed}.")
    
    score += qty_score
    if qty_score == 30:
        feedback.append("All component quantities correct.")

    # 3. Verify Manufacturing Order (10 + 10 + 30 pts)
    mo_data = result.get('mo_data')
    if mo_data:
        # Check qty
        if abs(mo_data.get('product_qty', 0) - 12) < 0.1:
            score += 10
            feedback.append("MO created for correct quantity (12).")
        else:
            feedback.append(f"MO quantity incorrect: {mo_data.get('product_qty')}.")

        state = mo_data.get('state')
        if state not in ['draft', 'cancel']:
            score += 10 # Confirmed
            if state == 'done':
                score += 30 # Done
                feedback.append("Manufacturing Order completed (Done).")
            else:
                feedback.append(f"MO is confirmed but not done (State: {state}).")
        else:
            feedback.append("MO is still in Draft state.")
    else:
        feedback.append("No Manufacturing Order found.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }