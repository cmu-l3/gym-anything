#!/usr/bin/env python3
"""
Verifier for weight_driven_infusion_verification task.

Verifies:
1. Devices created (Scale, Pump)
2. Report exists
3. Math accuracy checks:
   - Extracts weight and calculated rate from the user's report.
   - Verifies Rate = (Dose * Weight * 60) / Concentration
   - Dose = 10 mcg/kg/min
   - Conc = 2000 mcg/mL
"""

import json
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_weight_infusion(traj, env_info, task_info):
    # Copy result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Task parameters
    DOSE = 10.0      # mcg/kg/min
    CONC = 2000.0    # mcg/mL
    TARGET_WEIGHT = 12.5
    
    score = 0
    feedback = []

    # 1. Check Devices (40 pts)
    scale_created = result.get('scale_created', False)
    pump_created = result.get('pump_created', False)
    
    if scale_created:
        score += 20
        feedback.append("Scale created.")
    else:
        feedback.append("Scale NOT created.")
        
    if pump_created:
        score += 20
        feedback.append("Pump created.")
    else:
        feedback.append("Pump NOT created.")

    # 2. Check Report Existence (10 pts)
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', "")
    
    if report_exists and len(content.strip()) > 0:
        score += 10
        feedback.append("Report file exists.")
    else:
        feedback.append("Report file missing or empty.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Parse and Verify Math (50 pts)
    # Extract numbers from report
    # We look for two main numbers: Weight (kg) and Rate (mL/hr)
    
    # Simple regex to find numbers associated with units
    # Look for weight: "12.5" near "kg"
    weight_match = re.search(r'(\d+\.?\d*)\s*(?:kg|kilos)', content, re.IGNORECASE)
    # Look for rate: "3.75" near "ml/hr" or just the calculated value
    rate_match = re.search(r'(\d+\.?\d*)\s*(?:ml/hr|ml/h)', content, re.IGNORECASE)
    
    # If explicit units aren't found, try to find just numbers
    numbers = [float(x) for x in re.findall(r'(\d+\.?\d*)', content)]
    
    user_weight = None
    user_rate = None

    if weight_match:
        user_weight = float(weight_match.group(1))
    elif numbers:
        # Heuristic: Weight is likely the number closest to 12.5
        # This is lenient but handles unstructured text
        for n in numbers:
            if 10 <= n <= 15:
                user_weight = n
                break
    
    if rate_match:
        user_rate = float(rate_match.group(1))
    elif numbers and user_weight:
        # Rate should be derived from weight
        # Try to find the matching rate in the numbers
        expected = (DOSE * user_weight * 60) / CONC
        for n in numbers:
            if abs(n - expected) < 0.1:
                user_rate = n
                break

    # Verification Logic
    math_correct = False
    weight_reasonable = False

    if user_weight is not None:
        if 10.0 <= user_weight <= 15.0:
            score += 20 # Points for setting/using a pediatric weight
            weight_reasonable = True
            feedback.append(f"Used pediatric weight: {user_weight} kg.")
        else:
            feedback.append(f"Weight {user_weight} kg is not in target pediatric range (10-15 kg).")

        if user_rate is not None:
            expected_rate = (DOSE * user_weight * 60) / CONC
            if abs(user_rate - expected_rate) <= 0.1:
                score += 30
                math_correct = True
                feedback.append(f"Calculation correct: {user_rate} mL/hr matches weight {user_weight} kg.")
            else:
                feedback.append(f"Calculation incorrect. For {user_weight} kg, expected {expected_rate:.2f} mL/hr, got {user_rate}.")
        else:
            feedback.append("Could not identify calculated flow rate in report.")
    else:
        feedback.append("Could not identify weight in report.")

    # Pass Threshold
    passed = score >= 70 and math_correct and weight_reasonable

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }