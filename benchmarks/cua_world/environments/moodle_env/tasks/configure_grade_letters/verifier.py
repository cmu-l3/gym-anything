#!/usr/bin/env python3
"""
Verifier for Configure Grade Letters task.

Criteria:
1. Grade letters exist for the specific course context (NUR301).
2. Exactly 10 grade letter entries exist.
3. Each grade letter (A, A-, B+, etc.) matches the specific boundary requirement.
   - Tolerance: +/- 0.5% (to handle 93.000 vs 93)
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_grade_letters(traj, env_info, task_info):
    """
    Verify that grade letters are correctly configured for NUR301.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_boundaries = metadata.get('expected_boundaries', {
        "A": 93.0, "A-": 90.0, "B+": 87.0, "B": 83.0, "B-": 80.0,
        "C+": 77.0, "C": 73.0, "C-": 70.0, "D": 60.0, "F": 0.0
    })
    tolerance = metadata.get('boundary_tolerance', 0.5)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        current_count = result.get('current_count', 0)
        actual_boundaries = result.get('boundaries', {})
        context_id = result.get('context_id', 0)

        # 1. Check if ANY letters exist for this context (15 pts)
        if current_count > 0 and context_id > 0:
            score += 15
            feedback_parts.append("Custom grade letters created for course")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No custom grade letters found for NUR301 (did you override site defaults?)",
                "subscores": {"exists": False}
            }

        # 2. Check count (10 pts)
        # We expect exactly 10 letters defined in the spec
        expected_count = len(expected_boundaries)
        if current_count == expected_count:
            score += 10
            feedback_parts.append(f"Correct number of letters ({current_count})")
        else:
            feedback_parts.append(f"Incorrect number of letters: {current_count} (expected {expected_count})")

        # 3. Check specific boundaries (75 pts total)
        # Weighted points per letter
        # A, C, F are critical milestones
        weights = {
            "A": 10, "C": 10, "F": 10,
            "A-": 7, "B+": 7, "B": 7, "B-": 7, "C+": 7, "C-": 5, "D": 5
        }
        
        correct_letters = []
        incorrect_letters = []

        for letter, expected_val in expected_boundaries.items():
            actual_val = actual_boundaries.get(letter)
            
            if actual_val is None:
                incorrect_letters.append(f"{letter} (missing)")
                continue
                
            # Check tolerance
            try:
                actual_float = float(actual_val)
                if math.isclose(actual_float, expected_val, abs_tol=tolerance):
                    score += weights.get(letter, 5)
                    correct_letters.append(letter)
                else:
                    incorrect_letters.append(f"{letter} (got {actual_float}%, expected {expected_val}%)")
            except ValueError:
                incorrect_letters.append(f"{letter} (invalid value)")

        # Generate feedback
        if correct_letters:
            feedback_parts.append(f"Correct: {', '.join(correct_letters)}")
        if incorrect_letters:
            feedback_parts.append(f"Incorrect: {', '.join(incorrect_letters)}")

        # Pass logic
        # Must have created letters and got at least A (93) and C (73) correct
        critical_passed = "A" in correct_letters and "C" in correct_letters
        passed = (score >= 60) and critical_passed

        if not critical_passed:
            feedback_parts.append("FAIL: Critical boundaries A (93%) and C (73%) must be correct")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "count": current_count,
                "correct_letters": correct_letters
            }
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid result JSON"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}