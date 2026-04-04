#!/usr/bin/env python3
"""
Verifier for bulk_edit_featured_products task.

Criteria:
1. "Wireless Bluetooth Headphones" (WBH-001) is featured (25 pts)
2. "Organic Cotton T-Shirt" (OCT-BLK-M) is featured (25 pts)
3. "Merino Wool Sweater" (MWS-GRY-L) is featured (25 pts)
4. Precision: EXACTLY 3 products are featured (no extras) (15 pts)
5. Anti-gaming: State changed from initial (0) to 3 (10 pts)

Optional VLM verification for method (bulk vs single), but primary scoring is state-based.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_edit_featured_products(traj, env_info, task_info):
    """
    Verify that the 3 specific products were marked as featured.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    targets = result.get("target_status", {})
    final_count = result.get("final_featured_count", 0)
    initial_count = result.get("initial_featured_count", 0)

    # 3. Score Target Products (75 pts total)
    # WBH-001
    if targets.get("WBH-001"):
        score += 25
        feedback_parts.append("Headphones set to Featured (25/25)")
    else:
        feedback_parts.append("Headphones NOT Featured (0/25)")

    # OCT-BLK-M
    if targets.get("OCT-BLK-M"):
        score += 25
        feedback_parts.append("T-Shirt set to Featured (25/25)")
    else:
        feedback_parts.append("T-Shirt NOT Featured (0/25)")

    # MWS-GRY-L
    if targets.get("MWS-GRY-L"):
        score += 25
        feedback_parts.append("Sweater set to Featured (25/25)")
    else:
        feedback_parts.append("Sweater NOT Featured (0/25)")

    # 4. Score Precision (15 pts)
    # Only the 3 requested products should be featured
    if final_count == 3:
        # Check if we actually have the RIGHT 3 (implied by previous checks, but let's be safe)
        if targets.get("WBH-001") and targets.get("OCT-BLK-M") and targets.get("MWS-GRY-L"):
            score += 15
            feedback_parts.append("Precision Bonus: Exactly 3 items featured (15/15)")
        else:
            # Count is 3 but wrong items?
            feedback_parts.append(f"Count is 3 but targets missing. Precision bonus failed.")
    elif final_count > 3:
        feedback_parts.append(f"Precision Penalty: {final_count} items featured (expected 3). Did you select extra items? (0/15)")
    elif final_count < 3:
        # Already penalized by missing targets
        pass

    # 5. Score Anti-Gaming / Change Detection (10 pts)
    if initial_count == 0 and final_count > 0:
        score += 10
        feedback_parts.append("State change detected (10/10)")
    else:
        feedback_parts.append("No state change detected (0/10)")

    # 6. Final Evaluation
    passed = (score >= 70) and targets.get("WBH-001") and targets.get("OCT-BLK-M") and targets.get("MWS-GRY-L")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }