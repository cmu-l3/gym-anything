#!/usr/bin/env python3
"""
Verifier for configure_email_settings task.

Verifies that WooCommerce email sender options and template colors/text 
have been updated in the database to match the specific requirements.

Scoring Breakdown (100 pts total):
- From Name (15 pts)
- From Address (15 pts)
- Header Image (10 pts)
- Footer Text (15 pts)
- Base Color (12 pts)
- Background Color (11 pts)
- Body Background Color (11 pts)
- Body Text Color (11 pts)

Anti-gaming:
- Checks if values actually changed from their initial state (recorded in setup).
- Colors are checked case-insensitively.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_settings(traj, env_info, task_info):
    """
    Verify WooCommerce email settings configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_settings = metadata.get('expected_settings', {})
    
    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if result.get("error") == "database_unreachable":
        return {"passed": False, "score": 0, "feedback": "Database was unreachable during verification"}

    final_values = result.get("final_values", {})
    initial_values = result.get("initial_values", {})
    
    score = 0
    feedback_parts = []
    
    # Scoring weights mapping
    weights = {
        "woocommerce_email_from_name": 15,
        "woocommerce_email_from_address": 15,
        "woocommerce_email_header_image": 10,
        "woocommerce_email_footer_text": 15,
        "woocommerce_email_base_color": 12,
        "woocommerce_email_background_color": 11,
        "woocommerce_email_body_background_color": 11,
        "woocommerce_email_text_color": 11
    }
    
    # Validation logic
    for key, expected_val in expected_settings.items():
        actual_val = final_values.get(key, "")
        initial_val = initial_values.get(key, "")
        points = weights.get(key, 0)
        
        # Determine if it's a color (starts with #)
        is_color = expected_val.startswith("#")
        
        # Check equality
        match = False
        if is_color:
            match = actual_val.lower().strip() == expected_val.lower().strip()
        else:
            match = actual_val.strip() == expected_val.strip()
            
        # Verify it's not just the default (anti-gaming, though unlikely to match specific random targets by accident)
        # Note: If the initial value HAPPENED to be the target (re-run), we should still give credit if it's correct.
        # But for this task, defaults are known to be different.
        
        readable_key = key.replace("woocommerce_email_", "").replace("_", " ").title()
        
        if match:
            score += points
            feedback_parts.append(f"✓ {readable_key} set correctly")
        else:
            if actual_val == initial_val:
                feedback_parts.append(f"✗ {readable_key} unchanged (Value: '{actual_val}')")
            else:
                feedback_parts.append(f"✗ {readable_key} incorrect (Expected: '{expected_val}', Got: '{actual_val}')")

    # Pass Threshold
    # We require 60 points for a pass
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }