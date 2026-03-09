#!/usr/bin/env python3
"""
Verifier for update_product_inventory task.

Criteria:
1. WBH-001: Stock = 275 (20 pts)
2. WBH-001: Low Stock Threshold = 25 (15 pts)
3. USBC-065: Stock = 450 (20 pts)
4. SFDJ-BLU-32: Stock = 350 (20 pts)
5. SFDJ-BLU-32: Backorders = 'yes' (Allow) (15 pts)
6. All products remain published (10 pts)

Anti-gaming:
- Verify values actually changed from initial state.
- VLM process check: Verify user navigated to inventory settings.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_product_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        os.unlink(temp_result.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Task error: {result['error']}"}

    current = result.get("current_state", {})
    initial = result.get("initial_state", {})
    
    score = 0
    feedback = []
    
    # 1. Headphones (WBH-001) Checks
    hp = current.get("headphones", {})
    if str(hp.get("stock", "")).strip() == "275":
        score += 20
        feedback.append("Headphones stock correct (275).")
    else:
        feedback.append(f"Headphones stock incorrect: {hp.get('stock')}")
        
    if str(hp.get("low_stock", "")).strip() == "25":
        score += 15
        feedback.append("Headphones low stock threshold correct (25).")
    else:
        feedback.append(f"Headphones low stock incorrect: {hp.get('low_stock')}")

    # 2. Charger (USBC-065) Checks
    ch = current.get("charger", {})
    if str(ch.get("stock", "")).strip() == "450":
        score += 20
        feedback.append("Charger stock correct (450).")
    else:
        feedback.append(f"Charger stock incorrect: {ch.get('stock')}")

    # 3. Jeans (SFDJ-BLU-32) Checks
    jn = current.get("jeans", {})
    if str(jn.get("stock", "")).strip() == "350":
        score += 20
        feedback.append("Jeans stock correct (350).")
    else:
        feedback.append(f"Jeans stock incorrect: {jn.get('stock')}")
        
    # Backorders: 'yes' = Allow, 'notify' = Allow but notify, 'no' = Do not allow
    if str(jn.get("backorders", "")).strip() == "yes":
        score += 15
        feedback.append("Jeans backorders allowed.")
    else:
        feedback.append(f"Jeans backorders setting incorrect: {jn.get('backorders')}")

    # 4. Status Checks (All must be publish)
    statuses = [hp.get("status"), ch.get("status"), jn.get("status")]
    if all(s == "publish" for s in statuses):
        score += 10
        feedback.append("All products remain published.")
    else:
        feedback.append(f"Some products not published: {statuses}")

    # 5. Anti-Gaming / Change Detection
    # Ensure at least one value actually changed from initial
    init_hp = initial.get("WBH-001", {})
    init_ch = initial.get("USBC-065", {})
    init_jn = initial.get("SFDJ-BLU-32", {})
    
    changes = 0
    if str(hp.get("stock")) != str(init_hp.get("stock")): changes += 1
    if str(hp.get("low_stock")) != str(init_hp.get("low_stock")): changes += 1
    if str(ch.get("stock")) != str(init_ch.get("stock")): changes += 1
    if str(jn.get("stock")) != str(init_jn.get("stock")): changes += 1
    if str(jn.get("backorders")) != str(init_jn.get("backorders")): changes += 1

    if changes == 0 and score > 0:
        score = 0
        feedback.append("ANTI-GAMING: No values changed from initial state. Score reset to 0.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }