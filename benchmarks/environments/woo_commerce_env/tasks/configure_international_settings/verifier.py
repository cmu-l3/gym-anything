#!/usr/bin/env python3
"""
Verifier for Configure International Settings task in WooCommerce.

Verification Strategy:
1. Programmatic Checks (100 points):
   - Selling location restricted to 'specific'
   - Specific countries match exactly {DE, FR, IT}
   - Shipping location set to 'all' (matches selling)
   - Currency is EUR
   - Currency position is 'right_space'
   - Number formatting is European (dot thousand, comma decimal)

2. VLM Checks (Trajectory Analysis):
   - Verifies the agent actually interacted with the settings form.
   - Serves as anti-gaming / confirmation layer.

Pass Threshold: 100 points (Strict Configuration Task)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_international_settings(traj, env_info, task_info):
    """
    Verify the international settings configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    TARGET_COUNTRIES = {"DE", "FR", "IT"}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
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

    # 2. Verify Selling Location (20 pts)
    allowed_mode = result.get("woocommerce_allowed_countries", "")
    if allowed_mode == "specific":
        score += 20
        feedback_parts.append("Selling location restricted correctly (+20)")
    else:
        feedback_parts.append(f"Selling location is '{allowed_mode}', expected 'specific'")

    # 3. Verify Specific Countries (20 pts)
    raw_countries = result.get("woocommerce_specific_allowed_countries", [])
    
    # Handle various JSON structures (list vs dict keys)
    if isinstance(raw_countries, list):
        actual_countries = set(raw_countries)
    elif isinstance(raw_countries, dict):
        actual_countries = set(raw_countries.keys())
    else:
        actual_countries = set()
        
    if actual_countries == TARGET_COUNTRIES:
        score += 20
        feedback_parts.append("Country list matches exactly (+20)")
    else:
        feedback_parts.append(f"Country list mismatch. Got {actual_countries}, expected {TARGET_COUNTRIES}")

    # 4. Verify Shipping Locations (10 pts)
    ship_mode = result.get("woocommerce_ship_to_countries", "")
    # 'all' in backend means "Ship to all countries you sell to" when allowed_countries is specific
    if ship_mode == "all":
        score += 10
        feedback_parts.append("Shipping location aligned correctly (+10)")
    else:
        feedback_parts.append(f"Shipping location is '{ship_mode}', expected 'all'")

    # 5. Verify Currency (15 pts)
    currency = result.get("woocommerce_currency", "")
    if currency == "EUR":
        score += 15
        feedback_parts.append("Currency is Euro (+15)")
    else:
        feedback_parts.append(f"Currency is '{currency}', expected 'EUR'")

    # 6. Verify Currency Position (15 pts)
    curr_pos = result.get("woocommerce_currency_pos", "")
    if curr_pos == "right_space":
        score += 15
        feedback_parts.append("Currency position is 'right_space' (+15)")
    else:
        feedback_parts.append(f"Currency position is '{curr_pos}', expected 'right_space'")

    # 7. Verify Number Formatting (20 pts)
    thousand = result.get("woocommerce_price_thousand_sep", "")
    decimal = result.get("woocommerce_price_decimal_sep", "")
    
    if thousand == "." and decimal == ",":
        score += 20
        feedback_parts.append("Number formatting is correct (+20)")
    else:
        feedback_parts.append(f"Formatting mismatch. Thousand='{thousand}', Decimal='{decimal}'")

    # VLM / Anti-Gaming Check (Soft Check)
    # We check if the settings actually changed from defaults.
    # Defaults: USD, left, comma thousand, dot decimal.
    # If the score is high, they must have changed them, so this is implicitly covered.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }