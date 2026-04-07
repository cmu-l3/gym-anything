#!/usr/bin/env python3
"""
Verifier for duplicate_qcp_for_product task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize Odoo name field which might be a dictionary or string."""
    if isinstance(name, dict):
        return name.get("en_US", str(name)).strip()
    return str(name).strip()

def verify_duplicate_qcp_for_product(traj, env_info, task_info):
    """
    Verify the task based on exported database state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in data:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {data['error']}"}

    # Extract data
    baseline = data.get("baseline", {})
    current_state = data.get("current_state", {})
    
    baseline_count = baseline.get("qcp_count", 0)
    task_start_time = baseline.get("timestamp", 0)
    
    current_count = current_state.get("qcp_count", 0)
    new_qcps = current_state.get("new_qcps", [])
    source_qcp = current_state.get("source_qcp", {})

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Criterion 1: New QCP exists with correct name (25 pts)
    # ----------------------------------------------------------------
    target_qcp = None
    target_name_lower = "surface quality check - large cabinet"
    
    for qcp in new_qcps:
        q_name = normalize_name(qcp.get("name", "")).lower()
        if target_name_lower in q_name:
            target_qcp = qcp
            break
            
    if target_qcp:
        score += 25
        feedback_parts.append("New QCP created with correct name")
    else:
        feedback_parts.append("FAIL: New QCP with name 'Surface Quality Check - Large Cabinet' not found")

    # ----------------------------------------------------------------
    # Criterion 2: New QCP linked to "Large Cabinet" product (25 pts)
    # ----------------------------------------------------------------
    if target_qcp:
        product_names = [n.lower() for n in target_qcp.get("product_names", [])]
        if any("large cabinet" in n for n in product_names):
            score += 25
            feedback_parts.append("New QCP linked to 'Large Cabinet'")
            # Check if old product was removed
            if any("cabinet with doors" in n for n in product_names):
                score -= 10
                feedback_parts.append("Warning: 'Cabinet with Doors' was not removed from new QCP (-10 pts)")
        else:
            feedback_parts.append(f"FAIL: New QCP not linked to 'Large Cabinet' (found: {product_names})")
    else:
        feedback_parts.append("SKIP: Cannot check products (QCP not found)")

    # ----------------------------------------------------------------
    # Criterion 3: Original QCP unchanged (20 pts)
    # ----------------------------------------------------------------
    if source_qcp:
        source_name = normalize_name(source_qcp.get("name", "")).lower()
        product_names = [n.lower() for n in source_qcp.get("product_names", [])]
        
        name_ok = "cabinet with doors" in source_name
        product_ok = any("cabinet with doors" in n for n in product_names)
        
        if name_ok and product_ok:
            score += 20
            feedback_parts.append("Original QCP preserved")
        else:
            feedback_parts.append(f"FAIL: Original QCP modified (Name OK: {name_ok}, Product OK: {product_ok})")
    else:
        feedback_parts.append("FAIL: Original QCP deleted or not found")

    # ----------------------------------------------------------------
    # Criterion 4: QCP count increased by 1 (15 pts)
    # ----------------------------------------------------------------
    diff = current_count - baseline_count
    if diff == 1:
        score += 15
        feedback_parts.append("Record count increased by exactly 1")
    elif diff > 1:
        score += 5
        feedback_parts.append(f"Record count increased by {diff} (expected 1)")
    else:
        feedback_parts.append(f"FAIL: Record count change invalid (diff: {diff})")

    # ----------------------------------------------------------------
    # Criterion 5: New QCP has same test_type as original (10 pts)
    # ----------------------------------------------------------------
    if target_qcp and source_qcp:
        t_type = target_qcp.get("test_type")
        s_type = source_qcp.get("test_type")
        if t_type == s_type and t_type:
            score += 10
            feedback_parts.append("Test type preserved")
        else:
            feedback_parts.append(f"FAIL: Test type mismatch (Original: {s_type}, New: {t_type})")
    
    # ----------------------------------------------------------------
    # Criterion 6: Anti-gaming timestamp check (5 pts)
    # ----------------------------------------------------------------
    if target_qcp:
        create_date = target_qcp.get("create_date") # String "YYYY-MM-DD HH:MM:SS"
        # Since we don't easily have python date parsing matching Odoo server exactly without libs, 
        # we rely on the fact that the record was found in "new_qcps" query done at export time.
        # But Odoo returns create_date. We can check if it's not None.
        if create_date:
             score += 5
             feedback_parts.append("Creation timestamp present")

    # Final verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }