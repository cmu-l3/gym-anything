#!/usr/bin/env python3
"""
Verifier for retail_weight_barcode_setup task.

Criteria:
1. Barcode Rule Created (20 pts)
   - Must start with '24'
   - Must be type 'weight' (Weighted Product)
2. Pattern Syntax Correct (20 pts)
   - Must match Odoo syntax '24.....{NNDDD}' (or equiv) for 2 integer + 3 decimal weights
3. Product Created (20 pts)
   - Name contains "Prosciutto"
4. Product Configuration (40 pts)
   - Barcode matches '55001' (links to the ..... part)
   - UoM is 'kg'
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retail_weight_barcode_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # --- Check Barcode Rule ---
    rules = result.get('rules', [])
    target_rule = None
    
    # We are looking for a rule that handles prefix 24
    for rule in rules:
        pattern = rule.get('pattern', '')
        if pattern.startswith('24'):
            target_rule = rule
            break
            
    if target_rule:
        score += 20
        feedback.append("Barcode rule with prefix '24' found.")
        
        # Check Type
        if target_rule.get('type') == 'weight':
            score += 20
            feedback.append("Rule type is correctly set to 'Weighted Product'.")
        else:
            feedback.append(f"Rule type incorrect. Expected 'weight', got '{target_rule.get('type')}'.")
            
        # Check Pattern Syntax
        # Expected: 24.....{NNDDD}
        # Explanation: 24 (prefix) + 5 dots (product) + {NNDDD} (5 digits weight: 2 int, 3 dec)
        # We can be slightly flexible if they used {NN.DDD} which some versions support, 
        # but standard is {NNDDD} for EAN13 fixed length.
        # The prompt specifically asked for 2 integer, 3 decimal.
        pattern = target_rule.get('pattern', '')
        expected_suffix = "{NNDDD}"
        
        if expected_suffix in pattern and pattern.count('.') == 5:
            score += 20
            feedback.append(f"Pattern syntax '{pattern}' is correct.")
        else:
            feedback.append(f"Pattern syntax '{pattern}' is incorrect. Expected format like '24.....{{NNDDD}}'.")
    else:
        feedback.append("No barcode rule found starting with prefix '24'.")

    # --- Check Product ---
    product = result.get('product')
    
    if product:
        score += 20
        feedback.append(f"Product '{product.get('name')}' found.")
        
        # Check Barcode
        # The barcode on the product must match the '.....' part of the pattern.
        # If pattern is 24.....{...}, then for '2455001...', the product barcode must be 55001.
        if product.get('barcode') == '55001':
            score += 10
            feedback.append("Product barcode '55001' is correct.")
        else:
            feedback.append(f"Product barcode incorrect. Expected '55001', got '{product.get('barcode')}'.")
            
        # Check UoM
        uom_name = product.get('uom_name', '').lower()
        if 'kg' in uom_name or 'kilogram' in uom_name:
            score += 10
            feedback.append("Product Unit of Measure is 'kg'.")
        else:
            feedback.append(f"Product UoM incorrect. Expected 'kg', got '{uom_name}'.")
    else:
        feedback.append("Product 'Prosciutto di Parma' (or similar) not found.")

    # Final Calculation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }