#!/usr/bin/env python3
"""
Verifier for create_bom task in iDempiere.

Checks:
1. BOM Header exists with correct Search Key (PS-BOM-2024)
2. BOM is linked to correct Product (Patio Set)
3. BOM Name is correct (Patio Set Assembly)
4. Contains correct components (Patio Chair x4, Patio Table x1)
5. Anti-gaming: Record created during task session
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bom(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    # 1. Check BOM Header Existence (20 pts)
    bom_exists = result.get("bom_exists", False)
    bom_details = result.get("bom_details", {})
    
    if bom_exists and bom_details.get("value") == "PS-BOM-2024":
        score += 20
        feedback_parts.append("✅ BOM Header created")
    else:
        feedback_parts.append("❌ BOM Header not found or wrong Search Key")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Check Parent Product (15 pts)
    parent_name = bom_details.get("parent_product_name", "")
    if "Patio Set" in parent_name:
        score += 15
        feedback_parts.append("✅ Correct Parent Product")
    else:
        feedback_parts.append(f"❌ Incorrect Parent Product: {parent_name}")

    # 3. Check BOM Name (10 pts)
    bom_name = bom_details.get("name", "")
    if "Patio Set Assembly" in bom_name:
        score += 10
        feedback_parts.append("✅ Correct BOM Name")
    else:
        feedback_parts.append(f"⚠️ BOM Name mismatch: '{bom_name}'")

    # 4. Check Component Lines (30 pts split)
    lines = result.get("bom_lines", [])
    
    # Check Chair (15 pts)
    chair_found = False
    chair_qty_correct = False
    
    # Check Table (15 pts)
    table_found = False
    table_qty_correct = False
    
    for line in lines:
        prod_name = line.get("product_name", "")
        qty = float(line.get("qty", 0))
        is_active = line.get("isactive", "N") == "Y"
        
        if is_active:
            if "Patio Chair" in prod_name:
                chair_found = True
                if abs(qty - 4.0) < 0.01:
                    chair_qty_correct = True
            elif "Patio Table" in prod_name:
                table_found = True
                if abs(qty - 1.0) < 0.01:
                    table_qty_correct = True

    # Score Chair
    if chair_found:
        if chair_qty_correct:
            score += 15
            feedback_parts.append("✅ Patio Chair (Qty 4)")
        else:
            score += 5
            feedback_parts.append("⚠️ Patio Chair found but wrong Qty")
    else:
        feedback_parts.append("❌ Patio Chair component missing")

    # Score Table
    if table_found:
        if table_qty_correct:
            score += 15
            feedback_parts.append("✅ Patio Table (Qty 1)")
        else:
            score += 5
            feedback_parts.append("⚠️ Patio Table found but wrong Qty")
    else:
        feedback_parts.append("❌ Patio Table component missing")

    # 5. Active Status (5 pts)
    if bom_details.get("isactive") == "Y":
        score += 5
        feedback_parts.append("✅ BOM Active")
    else:
        feedback_parts.append("❌ BOM Inactive")

    # 6. Anti-Gaming / Timestamp Check (5 pts)
    task_start = result.get("task_start", 0)
    created_epoch = int(bom_details.get("created_epoch", 0))
    
    if created_epoch > task_start:
        score += 5
        feedback_parts.append("✅ Created during session")
    else:
        feedback_parts.append("⚠️ Timestamp verification failed")

    # Final result
    passed = score >= 60 and bom_exists and chair_found and table_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }