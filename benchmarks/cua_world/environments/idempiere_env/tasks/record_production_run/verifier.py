#!/usr/bin/env python3
"""
Verifier for record_production_run task.

Criteria:
1. A Production Record exists for 'Patio Set'.
2. Production Quantity is 5.
3. Contains line for 'Patio Chair' (approx 20 qty).
4. Contains line for 'Patio Table' (approx 5 qty).
5. Record was created/modified recently (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_production_run(traj, env_info, task_info):
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

    # Scoring variables
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check if record exists
    if not result.get('record_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Production record found for 'Patio Set'. Did you save it?"
        }
    
    score += 30
    feedback.append("Production record found.")
    
    # 2. Check header quantity
    try:
        prod_qty = float(result.get('production_qty', 0))
    except (ValueError, TypeError):
        prod_qty = 0
        
    if prod_qty == 5:
        score += 20
        feedback.append("Production quantity correct (5).")
    else:
        feedback.append(f"Production quantity incorrect. Expected 5, got {prod_qty}.")

    # 3. Check Lines (Components)
    lines = result.get('lines', [])
    chair_found = False
    table_found = False
    chair_qty_ok = False
    table_qty_ok = False
    
    for line in lines:
        p_name = line.get('product', '')
        try:
            qty = float(line.get('qty', 0))
        except:
            qty = 0
            
        if 'Patio Chair' in p_name:
            chair_found = True
            if 19 <= qty <= 21: # Tolerance for BOM variations, though explicit task said 20
                chair_qty_ok = True
                
        if 'Patio Table' in p_name:
            table_found = True
            if 4 <= qty <= 6: # Tolerance
                table_qty_ok = True

    # Score Chair
    if chair_found:
        score += 20
        feedback.append("Component 'Patio Chair' found.")
        if chair_qty_ok:
            score += 5
            feedback.append("Chair quantity correct (20).")
        else:
            feedback.append("Chair quantity incorrect.")
    else:
        feedback.append("Component 'Patio Chair' missing.")

    # Score Table
    if table_found:
        score += 20
        feedback.append("Component 'Patio Table' found.")
        if table_qty_ok:
            score += 5
            feedback.append("Table quantity correct (5).")
        else:
            feedback.append("Table quantity incorrect.")
    else:
        feedback.append("Component 'Patio Table' missing.")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }