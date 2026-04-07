#!/usr/bin/env python3
import json
import os
import sys
import logging
import tempfile
import math

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_stoichiometric_process(traj, env_info, task_info):
    """
    Verifies the Stoichiometric Process Modeling task.
    
    Criteria:
    1. Process 'Quicklime Production, stoichiometric' exists (20 pts)
    2. Input Limestone is 1000 kg (20 pts)
    3. Output Quicklime is 560 kg (20 pts)
    4. Emission CO2 is 440 kg (Mass Balance) (40 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract values
    metadata = task_info.get("metadata", {})
    expected_input = metadata.get("input_amount", 1000.0)
    expected_product = metadata.get("product_amount", 560.0)
    expected_co2 = metadata.get("expected_co2_amount", 440.0)
    tolerance = metadata.get("tolerance", 0.05) # 5% tolerance

    process_found = result.get("process_found", False)
    
    # Convert string values to floats, handling empty/invalid strings
    try:
        actual_input = float(result.get("input_limestone", 0))
    except (ValueError, TypeError):
        actual_input = 0.0
        
    try:
        actual_product = float(result.get("output_quicklime", 0))
    except (ValueError, TypeError):
        actual_product = 0.0
        
    try:
        actual_co2 = float(result.get("output_co2", 0))
    except (ValueError, TypeError):
        actual_co2 = 0.0

    score = 0
    feedback_parts = []
    
    # 3. Score calculation
    
    # Criterion 1: Process Created
    if process_found:
        score += 20
        feedback_parts.append("Process 'Quicklime Production, stoichiometric' created.")
    else:
        feedback_parts.append("Process not found.")
        return {"passed": False, "score": 0, "feedback": "Process 'Quicklime Production, stoichiometric' not found."}

    # Helper for tolerance checking
    def check_val(actual, expected, tol_percent):
        return math.isclose(actual, expected, rel_tol=tol_percent)

    # Criterion 2: Input Correct
    if check_val(actual_input, expected_input, tolerance):
        score += 20
        feedback_parts.append(f"Limestone input correct ({actual_input} kg).")
    else:
        feedback_parts.append(f"Limestone input incorrect (Expected {expected_input}, got {actual_input}).")

    # Criterion 3: Product Correct
    if check_val(actual_product, expected_product, tolerance):
        score += 20
        feedback_parts.append(f"Quicklime output correct ({actual_product} kg).")
    else:
        feedback_parts.append(f"Quicklime output incorrect (Expected {expected_product}, got {actual_product}).")

    # Criterion 4: CO2 Mass Balance (Anti-Gaming)
    # This is the most critical check. 
    # Logic: 1000 in = 560 product + X emission. X must be 440.
    if check_val(actual_co2, expected_co2, tolerance):
        score += 40
        feedback_parts.append(f"CO2 emission correct ({actual_co2} kg) - Mass balance preserved.")
    else:
        feedback_parts.append(f"CO2 emission incorrect (Expected {expected_co2}, got {actual_co2}). Mass balance violated.")

    # 4. Determine Pass/Fail
    # Threshold is 80 points (Must get mass balance correct OR everything else perfect + close)
    # The prompt specified 80 points threshold.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }