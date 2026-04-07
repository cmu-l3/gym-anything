#!/usr/bin/env python3
"""
Verifier stub for customer_revenue_vip_reward task.

This task requires the agent to:
1. Build a Views page at /admin/commerce/customer-revenue with aggregation
   (User relationship, GROUP BY username, COUNT orders, SUM totals),
   filtered to completed orders only, sorted by total descending.
2. Read the report to identify the highest-spending customer (johndoe).
3. Create an active promotion "VIP Reward - johndoe" with 20% off,
   coupon VIP-JOHNDOE (usage_limit=1), min order $100.
4. Add a "Customer Revenue" menu link under Commerce.

Full verification will be done via vlm_checklist_verifier.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_customer_revenue_vip_reward(traj, env_info, task_info):
    """Stub verifier — returns basic result from exported JSON."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        feedback = []
        score = 0

        # Basic checks from exported data
        if result.get('view_exists'):
            score += 25
            feedback.append("View exists")
        else:
            feedback.append("View NOT found")

        if result.get('path_registered'):
            score += 10
            feedback.append("Path registered")

        if result.get('promo_found'):
            score += 25
            feedback.append(f"Promotion found: {result.get('promo_name', '?')}")
        else:
            feedback.append("VIP promotion NOT found")

        if result.get('coupon_found') and result.get('coupon_linked'):
            score += 20
            feedback.append(f"Coupon linked: {result.get('coupon_code', '?')}")
        elif result.get('coupon_found'):
            score += 10
            feedback.append("Coupon found but not linked")
        else:
            feedback.append("Coupon NOT found")

        if result.get('menu_link_exists'):
            score += 10
            feedback.append("Menu link exists")

        if result.get('has_min_order'):
            score += 10
            feedback.append("Min order condition set")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }
