#!/usr/bin/env python3
"""
Verifier for Run Salary Query task in Oracle Database environment.

Uses ground truth validation from independent database query to prevent cheating.
The export script runs the actual query against the database and compares results.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_salary_query(traj, env_info, task_info):
    """
    Verify that the SQL query was executed correctly and results were saved.

    This verifier uses ground truth validation:
    1. The export script runs an independent database query to get expected employees
    2. It checks if those employees appear in the agent's result file
    3. This prevents cheating by creating fake files with keyword patterns

    Criteria:
    1. Result file exists at expected path
    2. File has proper structure (header + data rows)
    3. All expected employees from ground truth appear in results
    4. Results match the ground truth from independent database query
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_min_rows = metadata.get('expected_min_rows', 2)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/salary_query_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        feedback_parts = []

        # Extract validation data
        file_exists = result.get('result_file_exists', False)
        file_line_count = result.get('file_line_count', 0)
        ground_truth = result.get('ground_truth', {})
        validation = result.get('validation', {})

        expected_count = ground_truth.get('expected_count', 0)
        expected_employees = ground_truth.get('employees', [])
        matched_count = validation.get('matched_employee_count', 0)
        has_structure = validation.get('has_proper_structure', False)

        logger.info(f"Validation: file_exists={file_exists}, expected={expected_count}, matched={matched_count}")

        # Criterion 1: Result file exists (20 points)
        score = 0
        if file_exists:
            score += 20
            feedback_parts.append("Result file exists")
        else:
            feedback_parts.append("FAIL: Result file not found at /tmp/query_results.txt")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "file_exists": False,
                    "has_structure": False,
                    "ground_truth_match": 0,
                    "complete_match": False
                }
            }

        # Criterion 2: File has proper structure (20 points)
        if has_structure:
            score += 20
            feedback_parts.append("File has proper structure (header + data)")
        elif file_line_count > 1:
            score += 10  # Partial credit for having content
            feedback_parts.append("File has content but structure unclear")
        else:
            feedback_parts.append("File structure incomplete")

        # Criterion 3: Ground truth validation (60 points)
        # This is the critical anti-cheat check
        if expected_count == 0:
            # Database query failed or returned no results
            # NO partial credit - we can't verify so we can't trust the result
            feedback_parts.append("FAIL: Could not verify against database (ground truth unavailable)")
            # Return early with score based only on file existence/structure
            return {
                "passed": False,
                "score": score,  # Only file existence/structure points, no ground truth points
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "file_exists": file_exists,
                    "has_structure": has_structure,
                    "ground_truth_match": 0,
                    "expected_count": 0,
                    "complete_match": False
                },
                "error": "Ground truth validation failed - database query returned no results"
            }
        else:
            # Calculate match percentage
            match_ratio = matched_count / expected_count if expected_count > 0 else 0

            if match_ratio >= 1.0:
                # Perfect match - all expected employees found
                score += 60
                feedback_parts.append(f"All {expected_count} expected employees found in results")
            elif match_ratio >= 0.5:
                # Partial match
                points = int(60 * match_ratio)
                score += points
                feedback_parts.append(f"Found {matched_count}/{expected_count} expected employees")
            else:
                # Poor match - likely fake file
                points = int(60 * match_ratio)
                score += points
                feedback_parts.append(f"FAIL: Only {matched_count}/{expected_count} expected employees found")

            # Verify expected employee details
            if expected_employees:
                emp_names = [f"{e.get('first_name', '')} {e.get('last_name', '')} (${e.get('salary', 0)})"
                             for e in expected_employees[:3]]
                feedback_parts.append(f"Expected employees: {', '.join(emp_names)}")

        # Determine pass/fail
        # Must have: file exists (20) + some structure (10-20) + good match (30+) = 60+
        passed = score >= 70 and matched_count >= expected_count * 0.9

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "file_exists": file_exists,
                "has_structure": has_structure,
                "ground_truth_match": matched_count,
                "expected_count": expected_count,
                "complete_match": matched_count >= expected_count
            },
            "ground_truth_employees": expected_employees
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
