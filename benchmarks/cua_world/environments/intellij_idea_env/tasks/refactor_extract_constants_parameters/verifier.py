#!/usr/bin/env python3
"""
Verifier for Refactor Constants & Parameters Task.

Checks:
1. TAX_MULTIPLIER constant exists and is used.
2. SHIPPING_COST constant exists and is used.
3. Magic values (1.0825, 15.00) are removed from logic.
4. calculateFinalPrice signature accepts a 3rd parameter (targetTier).
5. Logic uses the new parameter instead of "PLATINUM".
6. CheckoutService.java was updated to pass the argument.
7. Project compiles.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_extract_constants_parameters(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []

    calc_content = result.get('calc_content', '')
    service_content = result.get('service_content', '')
    compile_success = result.get('compile_success', False)
    calc_modified = result.get('calc_modified', False)
    service_modified = result.get('service_modified', False)

    if not calc_modified:
        return {"passed": False, "score": 0, "feedback": "PricingCalculator.java was not modified."}

    # --- Criterion 1: Constants Defined (20 pts) ---
    # Look for: private static final double TAX_MULTIPLIER = 1.0825;
    # Allow loose spacing and visibility modifiers
    tax_regex = r'static\s+final\s+double\s+TAX_MULTIPLIER\s*=\s*1\.0825'
    ship_regex = r'static\s+final\s+double\s+SHIPPING_COST\s*=\s*15(\.0+)?'
    
    has_tax_const = bool(re.search(tax_regex, calc_content))
    has_ship_const = bool(re.search(ship_regex, calc_content))
    
    if has_tax_const and has_ship_const:
        score += 20
        feedback_parts.append("Constants TAX_MULTIPLIER and SHIPPING_COST defined correctly")
    elif has_tax_const or has_ship_const:
        score += 10
        feedback_parts.append("One of the required constants is missing or named incorrectly")
    else:
        feedback_parts.append("Constants not defined")

    # --- Criterion 2: Magic Numbers Removed (20 pts) ---
    # The numbers 1.0825 and 15.00 should NOT appear in the method body, only in declarations.
    # We strip the declarations first to check usage.
    body_content = re.sub(tax_regex, '', calc_content)
    body_content = re.sub(ship_regex, '', body_content)
    
    # Check if they still exist in the body
    magic_tax_left = '1.0825' in body_content
    magic_ship_left = '15.0' in body_content # Covers 15.0 and 15.00
    
    if not magic_tax_left and not magic_ship_left:
        score += 20
        feedback_parts.append("Magic numbers replaced with constants in logic")
    elif not magic_tax_left or not magic_ship_left:
        score += 10
        feedback_parts.append("Some magic numbers still present in logic")
    else:
        feedback_parts.append("Magic numbers still used in calculation logic")

    # --- Criterion 3: Parameter Extraction (20 pts) ---
    # Signature should have 3 arguments: (double ..., String ..., String targetTier)
    # Regex for signature: calculateFinalPrice(double x, String y, String targetTier)
    sig_regex = r'calculateFinalPrice\s*\(\s*double\s+\w+,\s*String\s+\w+,\s*String\s+targetTier\s*\)'
    
    if re.search(sig_regex, calc_content):
        score += 20
        feedback_parts.append("Method signature updated with 'targetTier' parameter")
    else:
        # Check if they added *any* 3rd string parameter
        alt_sig_regex = r'calculateFinalPrice\s*\(\s*double\s+\w+,\s*String\s+\w+,\s*String\s+\w+\s*\)'
        if re.search(alt_sig_regex, calc_content):
            score += 10
            feedback_parts.append("Method signature updated but parameter name is not 'targetTier'")
        else:
            feedback_parts.append("Method signature not updated correctly")

    # --- Criterion 4: Logic Updated (20 pts) ---
    # Logic should use the new parameter.
    # Look for: if (customerType.equals(targetTier))
    # NOT: if (customerType.equals("PLATINUM"))
    
    uses_param = 'customerType.equals(targetTier)' in calc_content or 'targetTier.equals(customerType)' in calc_content
    uses_literal = 'customerType.equals("PLATINUM")' in calc_content
    
    if uses_param and not uses_literal:
        score += 20
        feedback_parts.append("Logic updated to use extracted parameter")
    elif uses_param:
        score += 10
        feedback_parts.append("Logic uses parameter but literal comparison still present?")
    else:
        feedback_parts.append("Logic does not seem to use the new parameter")

    # --- Criterion 5: Compilation & Caller Update (20 pts) ---
    # If compilation succeeded, it implies CheckoutService.java was updated
    if compile_success:
        score += 20
        feedback_parts.append("Project compiles (Caller updated successfully)")
    else:
        # Check if caller was at least modified
        if service_modified:
            # Check if they updated the call manually even if compile failed
            if 'calculateFinalPrice(' in service_content and '"PLATINUM"' in service_content:
                 # Rudimentary check for 3 args
                 if re.search(r'calculateFinalPrice\([^,]+,[^,]+,[^,]+\)', service_content):
                     score += 10
                     feedback_parts.append("Caller modified with 3 args but compilation failed")
                 else:
                     feedback_parts.append("Caller modified but arguments look wrong")
        else:
            feedback_parts.append("Caller file (CheckoutService) not modified")

    # Pass Threshold: 80 points
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }