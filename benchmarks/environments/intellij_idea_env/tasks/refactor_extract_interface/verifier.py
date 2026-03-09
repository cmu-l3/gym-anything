#!/usr/bin/env python3
"""Verifier for refactor_extract_interface task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_extract_interface(traj, env_info, task_info):
    """
    Verify that the user extracted the PaymentGateway interface and updated dependencies.

    Criteria:
    1. PaymentGateway.java exists and is an interface (20 pts)
    2. Interface contains expected methods (charge, refund, verifyCard) (20 pts)
    3. StripeService implements PaymentGateway (20 pts)
    4. CheckoutService references PaymentGateway instead of StripeService (30 pts)
    5. Project compiles successfully (10 pts)
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    interface_exists = result.get('interface_exists', False)
    interface_content = result.get('interface_content', '')
    stripe_content = result.get('stripe_service_content', '')
    checkout_content = result.get('checkout_service_content', '')
    build_success = result.get('build_success', False)

    # --- Criterion 1: Interface Creation (20 pts) ---
    if interface_exists:
        # Verify it's actually an interface
        if re.search(r'public\s+interface\s+PaymentGateway', interface_content):
            score += 20
            feedback_parts.append("PaymentGateway interface created")
        else:
            score += 10
            feedback_parts.append("PaymentGateway file exists but is not declared as an interface")
    else:
        feedback_parts.append("PaymentGateway.java not found")

    # --- Criterion 2: Interface Methods (20 pts) ---
    # We expect charge, refund, verifyCard signature definitions (no bodies)
    if interface_exists:
        methods_found = 0
        expected_methods = {
            "charge": r'PaymentResult\s+charge\s*\(',
            "refund": r'PaymentResult\s+refund\s*\(',
            "verifyCard": r'boolean\s+verifyCard\s*\('
        }
        
        for name, pattern in expected_methods.items():
            if re.search(pattern, interface_content):
                methods_found += 1
        
        if methods_found == 3:
            score += 20
            feedback_parts.append("All expected methods found in interface")
        elif methods_found > 0:
            partial = int(20 * (methods_found / 3))
            score += partial
            feedback_parts.append(f"Only {methods_found}/3 methods found in interface")
        else:
            feedback_parts.append("No expected methods found in interface")
    
    # --- Criterion 3: Implementation (20 pts) ---
    # StripeService should implement PaymentGateway
    if re.search(r'public\s+class\s+StripeService\s+implements\s+PaymentGateway', stripe_content) or \
       re.search(r'public\s+class\s+StripeService\s+implements\s+.*PaymentGateway', stripe_content):
        score += 20
        feedback_parts.append("StripeService implements PaymentGateway")
    else:
        feedback_parts.append("StripeService does not implement PaymentGateway")

    # --- Criterion 4: Usage Refactoring (30 pts) ---
    # CheckoutService should use PaymentGateway field, not StripeService field
    # Bad: private final StripeService paymentService;
    # Good: private final PaymentGateway paymentService;
    
    field_refactored = False
    if re.search(r'private\s+(final\s+)?PaymentGateway\s+paymentService', checkout_content):
        field_refactored = True
    
    constructor_refactored = False
    # Check constructor injection: public CheckoutService(PaymentGateway paymentService)
    if re.search(r'public\s+CheckoutService\s*\(\s*PaymentGateway\s+', checkout_content):
        constructor_refactored = True
        
    if field_refactored and constructor_refactored:
        score += 30
        feedback_parts.append("CheckoutService fully refactored (field and constructor)")
    elif field_refactored:
        score += 20
        feedback_parts.append("CheckoutService field updated, but constructor might still use concrete class")
    elif constructor_refactored:
        score += 20
        feedback_parts.append("CheckoutService constructor updated, but field might still use concrete class")
    else:
        feedback_parts.append("CheckoutService still depends directly on concrete StripeService")

    # --- Criterion 5: Compilation (10 pts) ---
    if build_success:
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed (check refactoring errors)")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }