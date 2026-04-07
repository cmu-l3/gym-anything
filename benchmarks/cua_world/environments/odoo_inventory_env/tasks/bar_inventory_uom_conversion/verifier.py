#!/usr/bin/env python3
"""
Verifier for bar_inventory_uom_conversion task.

Scoring system (100 total, 80 to pass):
- 10 pts: 'Case of 6' UoM created correctly with ratio 6.
- 10 pts: 'Case of 12' UoM created correctly with ratio 12.
- 20 pts: PO line for Hendrick's Gin uses 'Case of 6' and quantity = 3.
- 20 pts: PO line for Woodford Reserve uses 'Case of 12' and quantity = 5.
- 20 pts: Hendrick's Gin final stock is exactly 18.
- 20 pts: Woodford Reserve final stock is exactly 60.

Anti-gaming: If the agent bypasses UoMs and just edits the PO line to 18 'Units', 
they fail the PO line checks and will cap at 40 points, failing the 80 threshold.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bar_inventory_uom_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/uom_conversion_result.json')
    pass_threshold = metadata.get('pass_threshold', 80)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {e}"}

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    score = 0
    feedback = []

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    uoms = result.get('uoms', [])
    pos = result.get('purchase_orders', [])
    stock = result.get('stock', {})

    # Locate the created UoMs (case insensitive match)
    uom_6 = next((u for u in uoms if u['name'].strip().lower() == 'case of 6'), None)
    uom_12 = next((u for u in uoms if u['name'].strip().lower() == 'case of 12'), None)

    # Criterion 1: Case of 6 created correctly
    if uom_6:
        # factor_inv represents the Ratio in Odoo when uom_type is 'bigger'
        ratio_6 = uom_6.get('factor_inv', 0) if uom_6.get('uom_type') == 'bigger' else uom_6.get('factor', 0)
        ratio_display = uom_6.get('ratio', 0)
        
        if abs(ratio_6 - 6) < 0.1 or abs(ratio_display - 6) < 0.1:
            score += 10
            feedback.append("PASS: 'Case of 6' UoM created with correct ratio (+10)")
        else:
            feedback.append("FAIL: 'Case of 6' UoM created but ratio is incorrect.")
    else:
        feedback.append("FAIL: 'Case of 6' UoM not found.")

    # Criterion 2: Case of 12 created correctly
    if uom_12:
        ratio_12 = uom_12.get('factor_inv', 0) if uom_12.get('uom_type') == 'bigger' else uom_12.get('factor', 0)
        ratio_display_12 = uom_12.get('ratio', 0)
        
        if abs(ratio_12 - 12) < 0.1 or abs(ratio_display_12 - 12) < 0.1:
            score += 10
            feedback.append("PASS: 'Case of 12' UoM created with correct ratio (+10)")
        else:
            feedback.append("FAIL: 'Case of 12' UoM created but ratio is incorrect.")
    else:
        feedback.append("FAIL: 'Case of 12' UoM not found.")

    # Retrieve the active PO
    po = pos[0] if pos else None
    gin_line, bbn_line = None, None

    if po:
        for line in po.get('lines', []):
            product_name = line.get('product_id', [0, ''])[1]
            if 'Gin' in product_name:
                gin_line = line
            elif 'Bourbon' in product_name:
                bbn_line = line

    # Criterion 3: PO Gin line updated correctly
    if gin_line and uom_6:
        if gin_line['product_uom'][0] == uom_6['id'] and gin_line['product_qty'] == 3:
            score += 20
            feedback.append("PASS: Hendrick's Gin PO line uses 'Case of 6' with Qty 3 (+20)")
        else:
            feedback.append(f"FAIL: Gin PO line has incorrect UoM or Qty (Qty: {gin_line['product_qty']}).")
    else:
        feedback.append("FAIL: Gin PO line missing or 'Case of 6' UoM missing.")

    # Criterion 4: PO Bourbon line updated correctly
    if bbn_line and uom_12:
        if bbn_line['product_uom'][0] == uom_12['id'] and bbn_line['product_qty'] == 5:
            score += 20
            feedback.append("PASS: Woodford Reserve PO line uses 'Case of 12' with Qty 5 (+20)")
        else:
            feedback.append(f"FAIL: Bourbon PO line has incorrect UoM or Qty (Qty: {bbn_line['product_qty']}).")
    else:
        feedback.append("FAIL: Bourbon PO line missing or 'Case of 12' UoM missing.")

    # Criterion 5: Hendrick's Gin Stock = 18
    gin_stock = stock.get('gin', 0)
    if gin_stock == 18:
        score += 20
        feedback.append("PASS: Hendrick's Gin internal stock is correctly 18 (+20)")
    else:
        feedback.append(f"FAIL: Hendrick's Gin stock is {gin_stock} (expected 18).")

    # Criterion 6: Woodford Reserve Stock = 60
    bbn_stock = stock.get('bbn', 0)
    if bbn_stock == 60:
        score += 20
        feedback.append("PASS: Woodford Reserve internal stock is correctly 60 (+20)")
    else:
        feedback.append(f"FAIL: Woodford Reserve stock is {bbn_stock} (expected 60).")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }