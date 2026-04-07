#!/usr/bin/env python3
"""
Verifier for lot_tracking_expiry_receipt task.

Scoring (100 points):
- Product 1 tracking enabled: 15 pts
- Product 2 tracking enabled: 15 pts
- Lot 1 created correctly: 15 pts
- Lot 2 created correctly: 15 pts
- Lot 1 expiry correct: 10 pts
- Lot 2 expiry correct: 10 pts
- Receipt validated (done): 20 pts

Pass Threshold: 65 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lot_tracking_expiry_receipt(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Task error: {result['error']}"}

    score = 0
    feedback = []

    # 1. Check Product Configuration (30 pts)
    if result.get('prod1_tracking') == 'lot':
        score += 15
        feedback.append("Product 1 tracking enabled (15/15)")
    else:
        feedback.append(f"Product 1 tracking incorrect: {result.get('prod1_tracking')} (0/15)")

    if result.get('prod2_tracking') == 'lot':
        score += 15
        feedback.append("Product 2 tracking enabled (15/15)")
    else:
        feedback.append(f"Product 2 tracking incorrect: {result.get('prod2_tracking')} (0/15)")

    # 2. Check Lots Existence (30 pts)
    expected = result.get('expected', {})
    
    if result.get('lot1_exists'):
        score += 15
        feedback.append(f"Lot {expected.get('prod1_lot')} created (15/15)")
    else:
        feedback.append(f"Lot {expected.get('prod1_lot')} missing (0/15)")

    if result.get('lot2_exists'):
        score += 15
        feedback.append(f"Lot {expected.get('prod2_lot')} created (15/15)")
    else:
        feedback.append(f"Lot {expected.get('prod2_lot')} missing (0/15)")

    # 3. Check Expiry Dates (20 pts)
    # Helper to compare YYYY-MM-DD
    def check_date(actual, expected):
        if not actual: return False
        # Odoo returns datetime string usually, or date string
        return str(actual).startswith(str(expected))

    if check_date(result.get('lot1_expiry'), expected.get('prod1_expiry')):
        score += 10
        feedback.append(f"Lot 1 expiry {expected.get('prod1_expiry')} correct (10/10)")
    else:
        feedback.append(f"Lot 1 expiry mismatch: got {result.get('lot1_expiry')} (0/10)")

    if check_date(result.get('lot2_expiry'), expected.get('prod2_expiry')):
        score += 10
        feedback.append(f"Lot 2 expiry {expected.get('prod2_expiry')} correct (10/10)")
    else:
        feedback.append(f"Lot 2 expiry mismatch: got {result.get('lot2_expiry')} (0/10)")

    # 4. Check Picking State (20 pts)
    if result.get('picking_state') == 'done':
        score += 20
        feedback.append("Receipt validated/done (20/20)")
    else:
        feedback.append(f"Receipt not validated (state: {result.get('picking_state')}) (0/20)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }