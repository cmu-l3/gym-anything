#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_revalue_inventory_stock(traj, env_info, task_info):
    """
    Verify the inventory revaluation task.
    
    Criteria:
    1. Inventory Revaluations module is enabled (20 pts).
    2. A revaluation entry exists (30 pts).
    3. The entry is for 'Aniseed Syrup' (20 pts).
    4. The new amount is 200.00 (30 pts).
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Module Enabled (20 pts)
    if result.get("module_enabled"):
        score += 20
        feedback.append("Inventory Revaluations module enabled.")
    else:
        feedback.append("Inventory Revaluations module NOT enabled.")
        
    # 2. Item Correct (20 pts)
    # 3. Entry Found (30 pts)
    # 4. Amount Correct (30 pts)
    
    if result.get("item_correct"):
        score += 20
        feedback.append("Correct inventory item (Aniseed Syrup) selected.")
    else:
        feedback.append("Target inventory item not found in revaluations.")
        
    if result.get("entry_found"):
        score += 30
        feedback.append("Revaluation entry successfully created.")
    else:
        feedback.append("No valid revaluation entry found.")
        
    if result.get("amount_correct"):
        score += 30
        feedback.append("Correct revaluation amount (200.00) set.")
    else:
        if result.get("item_correct"):
            feedback.append("Revaluation amount is incorrect (expected 200.00).")
            
    # Success threshold
    passed = score >= 70 and result.get("amount_correct")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }