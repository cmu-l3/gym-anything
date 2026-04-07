#!/usr/bin/env python3
"""
Verifier for manual_production_logging_adjustments task.

Scoring (100 pts total, pass threshold: 80):
  15 pts — Pellets Lot PP-1001 adjusted to 3000
  15 pts — Pellets Lot PP-1002 adjusted to 950
  15 pts — Blue Dye DYE-BLU-77 adjusted to 85
  15 pts — Red Dye DYE-RED-42 adjusted to 35
  20 pts — New Finished Good lot PB-BLU-4099 created and stocked to 45
  20 pts — Anti-gaming: Yellow Dye DYE-YEL-19 remains at 30 and untouched.
           (If Yellow Dye is modified, score capped at 50)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_production_adjustments(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/manual_production_result.json')
    expected_lots = metadata.get('expected_lots', {})
    new_lot = metadata.get('new_lot', {})
    anti_gaming_lot = metadata.get('anti_gaming_lot', {})
    pass_threshold = metadata.get('pass_threshold', 80)

    score = 0
    feedback_parts = []
    subscores = {}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found: {e}"
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse export result: {e}"
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    lots = result.get('lots', {})

    # Evaluate expected consumption/waste adjustments (15 pts each)
    for lot_name, lot_info in expected_lots.items():
        expected_qty = lot_info['expected_qty']
        prod_name = lot_info['product_name']
        
        lot_data = lots.get(lot_name, {})
        if not lot_data.get('found', False):
            feedback_parts.append(f"FAIL: Lot {lot_name} missing entirely.")
            subscores[lot_name] = False
            continue
            
        actual_qty = lot_data.get('qty', 0)
        
        # Check if the qty matches exactly (math requirement)
        if abs(actual_qty - expected_qty) < 0.01:
            score += 15
            subscores[lot_name] = True
            feedback_parts.append(f"PASS: {lot_name} correctly adjusted to {expected_qty} (+15)")
        else:
            subscores[lot_name] = False
            feedback_parts.append(f"FAIL: {lot_name} qty is {actual_qty}, expected {expected_qty}")

    # Evaluate new finished good lot creation (20 pts)
    new_lot_name = new_lot.get('name', 'PB-BLU-4099')
    new_expected_qty = new_lot.get('expected_qty', 45)
    
    new_lot_data = lots.get(new_lot_name, {})
    if new_lot_data.get('found', False):
        new_actual_qty = new_lot_data.get('qty', 0)
        if abs(new_actual_qty - new_expected_qty) < 0.01:
            score += 20
            subscores['new_lot_created'] = True
            feedback_parts.append(f"PASS: New lot {new_lot_name} created with correct qty {new_expected_qty} (+20)")
        else:
            subscores['new_lot_created'] = False
            # Partial credit if they created it but wrong quantity
            score += 10
            feedback_parts.append(f"PARTIAL: New lot {new_lot_name} created but wrong qty ({new_actual_qty} instead of {new_expected_qty}) (+10)")
    else:
        subscores['new_lot_created'] = False
        feedback_parts.append(f"FAIL: New finished good lot {new_lot_name} was not created.")

    # Evaluate anti-gaming lot (20 pts)
    ag_lot_name = anti_gaming_lot.get('name', 'DYE-YEL-19')
    ag_expected_qty = anti_gaming_lot.get('expected_qty', 30)
    
    ag_lot_data = lots.get(ag_lot_name, {})
    ag_actual_qty = ag_lot_data.get('qty', 0)
    ag_moves_count = ag_lot_data.get('moves_count', 0)
    
    # The setup script creates 1 stock move for the initial quant.
    # If there's >1 move, the agent performed an adjustment on it.
    ag_violated = False
    if abs(ag_actual_qty - ag_expected_qty) > 0.01:
        ag_violated = True
        feedback_parts.append(f"FAIL (Anti-Gaming): {ag_lot_name} quantity was modified to {ag_actual_qty}!")
    elif ag_moves_count > 1:
        ag_violated = True
        feedback_parts.append(f"FAIL (Anti-Gaming): {ag_lot_name} received unnecessary adjustment moves!")
        
    if not ag_violated:
        score += 20
        subscores['anti_gaming_passed'] = True
        feedback_parts.append(f"PASS: Anti-gaming check passed (Yellow Dye untouched) (+20)")
    else:
        subscores['anti_gaming_passed'] = False
        score = min(score, 50)
        feedback_parts.append("PENALTY: Anti-gaming violation capped total score at 50.")

    # Final tally
    passed = (score >= pass_threshold) and subscores.get('anti_gaming_passed', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }