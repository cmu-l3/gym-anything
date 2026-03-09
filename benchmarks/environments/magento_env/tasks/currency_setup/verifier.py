#!/usr/bin/env python3
"""Verifier for Currency Setup task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_currency_setup(traj, env_info, task_info):
    """
    Verify that multi-currency support was configured correctly.

    Criteria:
    1. EUR, GBP, CAD added to Allowed Currencies (10 pts each)
    2. USD remains in Allowed Currencies (5 pts)
    3. Default Display Currency is still USD (10 pts)
    4. Exchange Rates set correctly:
       - USD -> EUR: 0.9200 (15 pts)
       - USD -> GBP: 0.7900 (15 pts)
       - USD -> CAD: 1.3600 (15 pts)
    5. Bonus: At least 2 of 3 rates correct (10 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_allowed = set(metadata.get('expected_allowed', ["USD", "EUR", "GBP", "CAD"]))
    expected_default = metadata.get('expected_default', "USD")
    expected_rates = metadata.get('expected_rates', {"EUR": 0.9200, "GBP": 0.7900, "CAD": 1.3600})
    rate_tolerance = metadata.get('rate_tolerance', 0.001)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/currency_setup_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Parse allowed currencies (comma-separated string)
        current_allowed_str = result.get('current_allowed', '')
        current_allowed = set(x.strip() for x in current_allowed_str.split(',') if x.strip())
        
        current_default = result.get('current_default', '')
        current_rates = result.get('rates', {})

        logger.info(f"Result: allowed={current_allowed}, default={current_default}, rates={current_rates}")

        # Criterion 1 & 2: Allowed Currencies (35 pts total)
        # Check required currencies
        for curr in ["EUR", "GBP", "CAD"]:
            if curr in current_allowed:
                score += 10
                feedback_parts.append(f"{curr} enabled")
            else:
                feedback_parts.append(f"{curr} NOT enabled")
        
        # Check USD preserved
        if "USD" in current_allowed:
            score += 5
            feedback_parts.append("USD preserved")
        else:
            feedback_parts.append("USD accidentally disabled")

        # Criterion 3: Default Display Currency (10 pts)
        if current_default == expected_default:
            score += 10
            feedback_parts.append(f"Default currency is {expected_default}")
        else:
            feedback_parts.append(f"Default currency incorrect (expected {expected_default}, got {current_default})")

        # Criterion 4: Exchange Rates (45 pts total + 10 bonus)
        correct_rates_count = 0
        
        for curr, expected_val in expected_rates.items():
            actual_val = current_rates.get(curr)
            if actual_val is not None:
                try:
                    # Convert to float for comparison
                    actual_float = float(actual_val)
                    if abs(actual_float - expected_val) <= rate_tolerance:
                        score += 15
                        correct_rates_count += 1
                        feedback_parts.append(f"{curr} rate correct ({actual_float})")
                    else:
                        feedback_parts.append(f"{curr} rate incorrect (expected {expected_val}, got {actual_float})")
                except ValueError:
                    feedback_parts.append(f"{curr} rate invalid format")
            else:
                feedback_parts.append(f"{curr} rate NOT set")

        # Criterion 5: Bonus for partial completion of rates
        if correct_rates_count >= 2:
            score += 10
            feedback_parts.append("Bonus: Multiple rates correct")

        # Cap score at 100
        score = min(score, 100)
        
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }