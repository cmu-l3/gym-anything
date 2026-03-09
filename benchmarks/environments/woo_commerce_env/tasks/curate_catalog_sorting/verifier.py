#!/usr/bin/env python3
"""
Verifier for Curate Catalog Sorting task.

Verification Strategy:
1. Programmatic Check (Database):
   - "Merino Wool Sweater" menu_order should be < 0 (Priority 1)
   - "Slim Fit Denim Jeans" menu_order should be < 0 (Priority 2)
   - Sweater order should be < Jeans order (Sweater comes first)
   - Products should have been modified AFTER task start time.
2. Anti-Gaming:
   - Check modification timestamps.
   - Check against a control product (should likely stay 0).

Scoring:
- 40 pts: Sweater prioritised (menu_order < 0)
- 30 pts: Jeans prioritised (menu_order < 0)
- 30 pts: Correct hierarchy (Sweater < Jeans)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_curate_catalog_sorting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    products = result.get("products", {})
    sweater = products.get("sweater")
    jeans = products.get("jeans")
    control = products.get("control")
    task_start = result.get("task_start_ts", 0)

    # Basic Validation
    if not sweater or not jeans:
        return {"passed": False, "score": 0, "feedback": "Target products not found in database."}

    score = 0
    feedback_parts = []

    # 2. Check Modification Timestamps (Anti-Gaming)
    # Allow a small buffer (e.g., clock skew), generally mod_ts > task_start
    sweater_modified = sweater.get("modified_ts", 0) > task_start
    jeans_modified = jeans.get("modified_ts", 0) > task_start

    if not (sweater_modified or jeans_modified):
        return {"passed": False, "score": 0, "feedback": "No changes detected (products not modified during task)."}

    # 3. Check Menu Order Values
    sweater_order = sweater.get("menu_order", 0)
    jeans_order = jeans.get("menu_order", 0)
    control_order = control.get("menu_order", 0) if control else 0

    # Criterion 1: Sweater Prioritized (40 pts)
    # Must be less than default (0) AND less than control
    if sweater_order < 0 and sweater_order < control_order:
        score += 40
        feedback_parts.append("Sweater prioritized correctly.")
    else:
        feedback_parts.append(f"Sweater order ({sweater_order}) is not prioritized (<0).")

    # Criterion 2: Jeans Prioritized (30 pts)
    if jeans_order < 0 and jeans_order < control_order:
        score += 30
        feedback_parts.append("Jeans prioritized correctly.")
    else:
        feedback_parts.append(f"Jeans order ({jeans_order}) is not prioritized (<0).")

    # Criterion 3: Correct Hierarchy (30 pts)
    # Sweater must be strictly less than Jeans (appear first)
    if sweater_order < jeans_order:
        score += 30
        feedback_parts.append("Hierarchy correct (Sweater < Jeans).")
    elif sweater_order == jeans_order:
        feedback_parts.append("Hierarchy ambiguous (Sweater == Jeans).")
    else:
        feedback_parts.append("Hierarchy incorrect (Jeans < Sweater).")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }