#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_pos_terminal(traj, env_info, task_info):
    """
    Verify the creation of the POS Terminal configuration.
    
    Expected criteria:
    1. Record 'Express Lane 1' exists.
    2. Warehouse is 'HQ Warehouse'.
    3. Price List is 'Sale Price List'.
    4. Cash Book is 'HQ Cash'.
    5. Modify Price is 'N' (False).
    6. Record was created after task start.
    """
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract data
    record_found = result.get('record_found', False)
    name = result.get('name', '')
    warehouse = result.get('warehouse', '')
    pricelist = result.get('pricelist', '')
    cashbook = result.get('cashbook', '')
    is_modify_price = result.get('is_modify_price', 'Y') # Default to Y (unsafe) if not found
    created_ts = result.get('created_timestamp', 0)
    task_start = result.get('task_start_timestamp', 0)
    
    score = 0
    feedback_parts = []
    
    # 3. Evaluate criteria
    
    # Criterion 1: Record Exists (30 pts)
    if record_found and name == "Express Lane 1":
        score += 30
        feedback_parts.append("✅ POS Terminal record created.")
    else:
        feedback_parts.append("❌ POS Terminal record 'Express Lane 1' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Criterion 2: Warehouse (15 pts)
    # Accept exact match or partial if reasonable
    if "HQ Warehouse" in warehouse:
        score += 15
        feedback_parts.append("✅ Warehouse correct.")
    else:
        feedback_parts.append(f"❌ Warehouse incorrect (Expected: HQ Warehouse, Got: {warehouse}).")
        
    # Criterion 3: Price List (15 pts)
    if "Sale Price List" in pricelist or "Price List - Sale" in pricelist:
        score += 15
        feedback_parts.append("✅ Price List correct.")
    else:
        feedback_parts.append(f"❌ Price List incorrect (Expected: Sale Price List, Got: {pricelist}).")
        
    # Criterion 4: Cash Book (15 pts)
    if "HQ Cash" in cashbook:
        score += 15
        feedback_parts.append("✅ Cash Book correct.")
    else:
        feedback_parts.append(f"❌ Cash Book incorrect (Expected: HQ Cash, Got: {cashbook}).")
        
    # Criterion 5: Modify Price (15 pts)
    # DB stores 'Y' or 'N'
    if is_modify_price == 'N':
        score += 15
        feedback_parts.append("✅ 'Modify Price' disabled correctly.")
    else:
        feedback_parts.append("❌ 'Modify Price' should be unchecked (was enabled).")
        
    # Criterion 6: Anti-Gaming / Freshness (10 pts)
    # Allow a small buffer for clock skew, though docker host/container usually sync
    if created_ts > task_start:
        score += 10
        feedback_parts.append("✅ Record created during task session.")
    else:
        feedback_parts.append("⚠️ Record timestamp predates task start (pre-existing?).")
        
    # Final calculation
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }