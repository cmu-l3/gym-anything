#!/usr/bin/env python3
"""
Verifier for enum_refactor_constants task.

Checks:
1. Enum Existence & Structure (Constants, Methods) - 38 pts
2. Refactoring Implementation (Usage in other files) - 30 pts
3. Cleanup (Old constants removed) - 10 pts
4. Compilation & Tests - 22 pts
"""

import json
import tempfile
import os
import re
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enum_refactor(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get('files', {})
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback = []
    
    # ==========================================================================
    # Criterion 1: Enum Existence & Structure (38 pts)
    # ==========================================================================
    pt_content = files.get('PaymentType.java')
    
    if pt_content and "enum PaymentType" in pt_content:
        score += 10
        feedback.append("PaymentType enum created.")
        
        # Check constants
        constants = ["CREDIT_CARD", "DEBIT_CARD", "BANK_TRANSFER", "DIGITAL_WALLET"]
        missing_constants = [c for c in constants if c not in pt_content]
        if not missing_constants:
            score += 10
            feedback.append("All enum constants present.")
        else:
            feedback.append(f"Missing constants: {missing_constants}")

        # Check for getFeeRate method and logic
        # Robust check: look for method def and return values
        if "double getFeeRate" in pt_content or "double getFeeRate()" in pt_content:
            score += 5
            # Verify rate values exist in file (0.029, 0.015, 0.005, 0.025)
            rates_present = all(r in pt_content for r in ["0.029", "0.015", "0.005", "0.025"])
            if rates_present:
                score += 5
                feedback.append("Fee rates implemented correcty.")
            else:
                feedback.append("getFeeRate method found but some rate values are missing.")
        else:
            feedback.append("getFeeRate() method missing in Enum.")

        # Check for getDisplayName method
        if "String getDisplayName" in pt_content:
            score += 4
            names_present = all(n in pt_content for n in ["Credit Card", "Debit Card", "Bank Transfer", "Digital Wallet"])
            if names_present:
                score += 4
                feedback.append("Display names implemented correctly.")
            else:
                feedback.append("getDisplayName method found but some names missing.")
        else:
            feedback.append("getDisplayName() method missing.")
            
    else:
        feedback.append("PaymentType.java not found or is not an enum.")

    # ==========================================================================
    # Criterion 2: Refactoring Usage (30 pts)
    # ==========================================================================
    
    # Check PaymentProcessor signature
    pp_content = files.get('PaymentProcessor.java', "")
    if "processPayment(double amount, PaymentType" in pp_content:
        score += 10
        feedback.append("PaymentProcessor refactored to use PaymentType.")
    elif "processPayment(double amount, int" in pp_content:
        feedback.append("PaymentProcessor still uses int.")
    else:
        feedback.append("PaymentProcessor signature unclear.")

    # Check FeeCalculator usage
    fc_content = files.get('FeeCalculator.java', "")
    if ".getFeeRate()" in fc_content:
        score += 10
        feedback.append("FeeCalculator uses Enum behavior (getFeeRate).")
    elif "switch" in fc_content:
        feedback.append("FeeCalculator still uses switch statement (should use Enum method).")

    # Check PaymentReport usage
    pr_content = files.get('PaymentReport.java', "")
    if ".getDisplayName()" in pr_content:
        score += 5
        feedback.append("PaymentReport uses Enum behavior (getDisplayName).")
    elif "switch" in pr_content:
        feedback.append("PaymentReport still uses switch statement.")

    # Check Validator signature
    pv_content = files.get('PaymentValidator.java', "")
    if "validate(double amount, PaymentType" in pv_content:
        score += 5
        feedback.append("PaymentValidator refactored.")

    # ==========================================================================
    # Criterion 3: Cleanup (10 pts)
    # ==========================================================================
    pc_content = files.get('PaymentConstants.java')
    
    # File should either not exist, or be empty, or not contain the constants
    if not pc_content:
        score += 10
        feedback.append("PaymentConstants.java deleted.")
    elif "public static final int CREDIT_CARD" not in pc_content:
        score += 10
        feedback.append("PaymentConstants.java cleaned up.")
    else:
        feedback.append("PaymentConstants.java still contains legacy constants.")

    # ==========================================================================
    # Criterion 4: Compilation & Tests (22 pts)
    # ==========================================================================
    mvn_exit_code = result.get('mvn_exit_code', 1)
    tests_run = result.get('tests_run', 0)
    tests_failures = result.get('tests_failures', 0)
    tests_errors = result.get('tests_errors', 0)
    
    if mvn_exit_code == 0:
        score += 10
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("Project compilation failed.")
        
    if tests_run >= 8 and tests_failures == 0 and tests_errors == 0:
        score += 12
        feedback.append(f"All {tests_run} tests passed.")
    elif tests_run > 0:
        # Partial credit for tests
        pass_rate = (tests_run - tests_failures - tests_errors) / tests_run
        points = int(12 * pass_rate)
        score += points
        feedback.append(f"Tests passing: {tests_run - tests_failures - tests_errors}/{tests_run}.")
    else:
        feedback.append("No tests run.")

    # ==========================================================================
    # VLM Trajectory Check (Bonus/Validation)
    # ==========================================================================
    # We verify the VLM score from the trajectory if available, mostly as a sanity check
    # But for code tasks, programmatic verification is primary.
    # We will assume trajectory VLM is handled by the framework wrapper if needed, 
    # but here we focus on the code result.
    
    # Final Score Calculation
    passed = score >= 60 and mvn_exit_code == 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "compilation": mvn_exit_code == 0,
            "tests_passed": tests_failures == 0 and tests_errors == 0
        }
    }