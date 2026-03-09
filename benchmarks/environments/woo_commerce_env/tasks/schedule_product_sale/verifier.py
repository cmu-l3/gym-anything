#!/usr/bin/env python3
"""
Verifier for schedule_product_sale task.

Verification Strategy:
1. Primary: Database checks for sale price and dates (Logic ported from bash design).
2. Anti-gaming: Check if modification timestamp is after task start.
3. Anti-gaming: Ensure regular price wasn't accidentally changed.
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_product_sale(traj, env_info, task_info):
    """
    Verify the product sale schedule.
    """
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

    # Scoring Config
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    product_found = result.get("product_found", False)
    sale_price = result.get("sale_price", "")
    sale_from = result.get("sale_date_from", "0")
    sale_to = result.get("sale_date_to", "0")
    regular_price = result.get("regular_price", "")
    post_modified = result.get("post_modified", 0)
    task_start = result.get("task_start_time", 0)

    if not product_found:
        return {"passed": False, "score": 0, "feedback": "Target product not found in database"}

    # Criterion 1: Sale Price Correct (30 pts)
    if sale_price == "49.99":
        score += 30
        feedback_parts.append("Sale price correct (49.99)")
    else:
        feedback_parts.append(f"Sale price incorrect (Expected 49.99, Got '{sale_price}')")

    # Criterion 2: Sale Start Date Correct (25 pts)
    # Target: 2025-07-01. Timestamp ~1751241600. Allow +/- 24 hours for timezone diffs.
    # 2025-07-01 UTC midnight is 1751328000
    try:
        ts_from = int(sale_from) if sale_from and sale_from != "0" else 0
        # Range: June 30 2025 to July 2 2025
        if 1751241600 <= ts_from <= 1751414400:
            score += 25
            feedback_parts.append("Start date correct (2025-07-01)")
        else:
            feedback_parts.append(f"Start date incorrect (Got timestamp {ts_from})")
    except ValueError:
        feedback_parts.append("Start date invalid")

    # Criterion 3: Sale End Date Correct (25 pts)
    # Target: 2025-07-07. Timestamp ~1751846400.
    # 2025-07-07 UTC midnight is 1751846400
    try:
        ts_to = int(sale_to) if sale_to and sale_to != "0" else 0
        # Range: July 6 2025 to July 8 2025
        if 1751760000 <= ts_to <= 1751932800:
            score += 25
            feedback_parts.append("End date correct (2025-07-07)")
        else:
            feedback_parts.append(f"End date incorrect (Got timestamp {ts_to})")
    except ValueError:
        feedback_parts.append("End date invalid")

    # Criterion 4: Regular Price Unchanged (10 pts)
    if regular_price == "79.99":
        score += 10
        feedback_parts.append("Regular price preserved")
    else:
        feedback_parts.append(f"Regular price changed (Expected 79.99, Got '{regular_price}')")

    # Criterion 5: Modified After Task Start (10 pts)
    if post_modified > task_start:
        score += 10
        feedback_parts.append("Product updated during task")
    else:
        feedback_parts.append("Product not updated during task")

    # Pass threshold: 70 points
    # Must have correct price and at least one correct date to be considered "mostly working"
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }