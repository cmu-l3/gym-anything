#!/usr/bin/env python3
"""
Verifier for Configure Tiered Promotions task.

Verifies:
1. Promotions exist for Tier 1 ($15 off) and Tier 2 ($50 off).
2. Logic check: $150 cart gets exactly $15 off.
3. Logic check: $400 cart gets exactly $50 off (NOT $65).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tiered_promotions(traj, env_info, task_info):
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
            
        score = 0
        feedback_parts = []
        
        # Check if simulation ran
        if result.get('simulation_failed'):
            feedback_parts.append("Warning: Pricing simulation failed to run, verification limited to DB checks.")

        # Criterion 1: Tier 1 exists (20 pts)
        if result.get('tier1_exists'):
            score += 20
            feedback_parts.append("Tier 1 promotion found")
        else:
            feedback_parts.append("Tier 1 promotion NOT found or inactive")

        # Criterion 2: Tier 2 exists (20 pts)
        if result.get('tier2_exists'):
            score += 20
            feedback_parts.append("Tier 2 promotion found")
        else:
            feedback_parts.append("Tier 2 promotion NOT found or inactive")

        # Criterion 3: Scenario $150 (30 pts)
        # Should be exactly 15
        discount_150 = float(result.get('scenario_150', 0))
        if abs(discount_150 - 15.0) < 0.01:
            score += 30
            feedback_parts.append("$150 Order: Correctly discounted by $15.00")
        elif discount_150 > 0:
            score += 10
            feedback_parts.append(f"$150 Order: Incorrect discount ${discount_150} (expected $15.00)")
        else:
            feedback_parts.append("$150 Order: No discount applied")

        # Criterion 4: Scenario $400 (30 pts)
        # Should be exactly 50 (NO STACKING)
        discount_400 = float(result.get('scenario_400', 0))
        if abs(discount_400 - 50.0) < 0.01:
            score += 30
            feedback_parts.append("$400 Order: Correctly discounted by $50.00 (No Stacking)")
        elif abs(discount_400 - 65.0) < 0.01:
            # Logic fail: Stacking happened
            feedback_parts.append("$400 Order: FAILED - Discount was $65.00 (Promotions Stacked!)")
        elif discount_400 > 0:
            feedback_parts.append(f"$400 Order: Incorrect discount ${discount_400} (expected $50.00)")
        else:
            feedback_parts.append("$400 Order: No discount applied")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}