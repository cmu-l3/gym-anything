#!/usr/bin/env python3
"""Verifier for chemistry_molar_mass_tool task.

Checks that the agent created a functioning Python parser for chemical formulas
and accurately processed both the required text file output and hidden dynamic test cases.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_float(output_str):
    """Safely extract a float from the agent's output.
    Handles extra whitespace or stray characters if they didn't follow the 'ONLY numbers' rule perfectly."""
    try:
        matches = re.findall(r"[-+]?\d*\.\d+|\d+", str(output_str))
        if matches:
            return float(matches[-1])
        return None
    except Exception:
        return None

def verify_chemistry_molar_mass_tool(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_masses = metadata.get('expected_masses', {})
    dynamic_tests_expected = metadata.get('dynamic_tests', {})

    # Retrieve export result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    TOLERANCE = 0.02 # Allow minor floating point discrepancies

    # 1. Evaluate static text file `results.txt` (Total: 35 points)
    if result.get('results_exists'):
        content = result.get('results_content', '')
        
        # Base format check (10 points)
        if re.search(r"H2O:\s*\d+", content) and re.search(r"NaCl:\s*\d+", content):
            score += 10
            feedback.append("results.txt formatting correct")
        else:
            feedback.append("results.txt formatting missing or incorrect")

        # Specific compound checks (5x5 = 25 points)
        for compound, expected_mass in expected_masses.items():
            # Look for lines like "H2O: 18.02"
            pattern = rf"{re.escape(compound)}:\s*([-+]?\d*\.\d+|\d+)"
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                actual_mass = float(match.group(1))
                if abs(actual_mass - expected_mass) <= TOLERANCE:
                    score += 5
                    feedback.append(f"{compound} correct in results.txt")
                else:
                    feedback.append(f"{compound} incorrect in results.txt (expected {expected_mass}, got {actual_mass})")
            else:
                feedback.append(f"{compound} missing from results.txt")
    else:
        feedback.append("results.txt not found")

    # 2. Evaluate Dynamic Script Execution (Total: 65 points)
    dynamic_tests = result.get('dynamic_tests', {})
    dynamic_passed = 0
    
    if result.get('script_exists'):
        # Test 1: HCl (15 points) - simple two-char element mix
        hcl_out = extract_float(dynamic_tests.get('HCl', ''))
        if hcl_out is not None and abs(hcl_out - dynamic_tests_expected['HCl']) <= TOLERANCE:
            score += 15
            dynamic_passed += 1
            feedback.append("Dynamic test HCl passed")
        else:
            feedback.append(f"Dynamic test HCl failed (output: {dynamic_tests.get('HCl', '')})")

        # Test 2: Na2SO4 (15 points) - complex multi-element with explicit numbers
        na2so4_out = extract_float(dynamic_tests.get('Na2SO4', ''))
        if na2so4_out is not None and abs(na2so4_out - dynamic_tests_expected['Na2SO4']) <= TOLERANCE:
            score += 15
            dynamic_passed += 1
            feedback.append("Dynamic test Na2SO4 passed")
        else:
            feedback.append(f"Dynamic test Na2SO4 failed (output: {dynamic_tests.get('Na2SO4', '')})")

        # Test 3: C8H10N4O2 (20 points) - large molecule, tests strict repetition logic
        caffeine_out = extract_float(dynamic_tests.get('C8H10N4O2', ''))
        if caffeine_out is not None and abs(caffeine_out - dynamic_tests_expected['C8H10N4O2']) <= TOLERANCE:
            score += 20
            dynamic_passed += 1
            feedback.append("Dynamic test C8H10N4O2 passed")
        else:
            feedback.append(f"Dynamic test C8H10N4O2 failed (output: {dynamic_tests.get('C8H10N4O2', '')})")

        # Test 4: O2 (15 points) - starts with implicit 1 modifier rule edge cases
        o2_out = extract_float(dynamic_tests.get('O2', ''))
        if o2_out is not None and abs(o2_out - dynamic_tests_expected['O2']) <= TOLERANCE:
            score += 15
            dynamic_passed += 1
            feedback.append("Dynamic test O2 passed")
        else:
            feedback.append(f"Dynamic test O2 failed (output: {dynamic_tests.get('O2', '')})")
    else:
        feedback.append("molar_mass.py script not found, cannot run dynamic tests")

    # Determine passing state
    # Pass requires a score of 70 AND passing at least 2 dynamic tests (to prevent hardcoding text file output)
    passed = (score >= 70) and (dynamic_passed >= 2)

    if passed:
        feedback.insert(0, "SUCCESS: Valid chemical formula parser created.")
    else:
        feedback.insert(0, "FAILED: Parser is incomplete or hardcoded.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "results_txt_exists": result.get('results_exists', False),
            "script_exists": result.get('script_exists', False),
            "dynamic_tests_passed": dynamic_passed
        }
    }