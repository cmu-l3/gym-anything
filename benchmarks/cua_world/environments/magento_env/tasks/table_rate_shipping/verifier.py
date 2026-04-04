#!/usr/bin/env python3
"""Verifier for Table Rate Shipping task in Magento.

Task: Configure Table Rates for Main Website scope, set title, condition,
and import a CSV with specific weight-based rates.

Criteria:
1. Table Rates enabled for Main Website scope (20 pts)
2. Title set to 'Heavy Goods Shipping' (10 pts)
3. Condition set to 'Weight vs. Destination' (package_weight) (10 pts)
4. Rate 1 (0lbs -> $15) imported correctly (30 pts)
5. Rate 2 (10lbs -> $25) imported correctly (30 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_table_rate_shipping(traj, env_info, task_info):
    """
    Verify table rate shipping configuration and data import.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/table_rate_shipping_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    expected_title = "Heavy Goods Shipping"
    expected_condition = "package_weight"

    # 1. Check Configuration (Website Scope) - 40 pts total
    
    # Active (20 pts)
    config_active = str(result.get('config_active', '0')).strip()
    if config_active == '1':
        score += 20
        feedback_parts.append("Table Rates enabled for Main Website (20 pts)")
    else:
        feedback_parts.append("Table Rates NOT enabled for Main Website scope")

    # Title (10 pts)
    config_title = result.get('config_title', '').strip()
    if expected_title.lower() in config_title.lower():
        score += 10
        feedback_parts.append(f"Title correct: '{config_title}' (10 pts)")
    else:
        feedback_parts.append(f"Title incorrect: expected '{expected_title}', got '{config_title}'")

    # Condition (10 pts)
    config_condition = result.get('config_condition', '').strip()
    if config_condition == expected_condition:
        score += 10
        feedback_parts.append("Condition correct: Weight vs. Destination (10 pts)")
    else:
        feedback_parts.append(f"Condition incorrect: expected '{expected_condition}', got '{config_condition}'")

    # 2. Check Imported Rates - 60 pts total
    
    imported_rates = result.get('imported_rates', [])
    
    # We look for specific rate signatures
    # Rate 1: US, Weight 0 (approx), Price 15
    rate_1_found = False
    rate_2_found = False
    
    for rate in imported_rates:
        country = rate.get('country', '')
        weight = float(rate.get('weight', -1))
        price = float(rate.get('price', -1))
        
        if country == 'US':
            # Check Rate 1: Weight 0, Price 15
            if abs(weight - 0.0) < 0.01 and abs(price - 15.0) < 0.01:
                rate_1_found = True
            
            # Check Rate 2: Weight 10, Price 25
            if abs(weight - 10.0) < 0.01 and abs(price - 25.0) < 0.01:
                rate_2_found = True

    if rate_1_found:
        score += 30
        feedback_parts.append("Rate 1 (0lbs -> $15) found (30 pts)")
    else:
        feedback_parts.append("Rate 1 (0lbs -> $15) NOT found in database")

    if rate_2_found:
        score += 30
        feedback_parts.append("Rate 2 (10lbs -> $25) found (30 pts)")
    else:
        feedback_parts.append("Rate 2 (10lbs -> $25) NOT found in database")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }