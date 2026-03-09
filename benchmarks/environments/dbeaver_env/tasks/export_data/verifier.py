#!/usr/bin/env python3
"""
Verifier for Export Data task in DBeaver

Uses copy_from_env to read pre-exported verification data.
Requires:
1. File exists at EXACT expected path (no alternatives)
2. File has ALL required columns (CustomerId, FirstName, LastName, Email)
3. File has correct number of rows (~59)
4. Content validates as customers table data
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_data(traj, env_info, task_info):
    """
    Verify that the customers table was exported to CSV.

    Criteria (stricter validation):
    1. File exists at EXACT expected path (REQUIRED)
    2. File has ALL required columns (REQUIRED)
    3. Correct number of rows (59 ± 2)
    4. Content validates as customers data (REQUIRED)
    5. File was created during task
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_row_count = metadata.get('expected_row_count', 59)
    expected_export_path = metadata.get('expected_export_path', '/home/ga/Documents/exports/customers_export.csv')
    required_columns = metadata.get('required_columns', ['CustomerId', 'FirstName', 'LastName', 'Email'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/export_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Initialize scoring
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        critical_failures = []

        # Extract result data
        file_exists = result.get('file_exists', False)
        correct_path = result.get('correct_path', False)
        actual_path = result.get('actual_path', '')
        expected_path = result.get('expected_path', expected_export_path)
        file_size = result.get('file_size_bytes', 0)
        row_count = result.get('row_count', 0)
        column_count = result.get('column_count', 0)
        has_all_columns = result.get('has_all_columns', False)
        has_customerid = result.get('has_customerid_column', False)
        has_firstname = result.get('has_firstname_column', False)
        has_lastname = result.get('has_lastname_column', False)
        has_email = result.get('has_email_column', False)
        content_valid = result.get('content_valid', False)
        customers_matched = result.get('customers_matched', 0)
        min_customers_required = result.get('min_customers_required', 5)
        created_recently = result.get('created_recently', False)

        logger.info(f"Result: exists={file_exists}, correct_path={correct_path}, "
                   f"rows={row_count}, customers_matched={customers_matched}, content_valid={content_valid}")

        # CRITICAL CHECK 1: File must exist at EXACT path
        if not file_exists:
            critical_failures.append(f"Export file NOT found at {expected_path}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Export file not found. Must export to exactly: {expected_path}",
                "subscores": {
                    "file_exists": False,
                    "correct_path": False,
                    "has_all_columns": False,
                    "correct_row_count": False,
                    "content_valid": False
                }
            }

        if not correct_path:
            critical_failures.append(f"File at wrong path: {actual_path} (expected {expected_path})")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: File at wrong path. Must export to exactly: {expected_path}",
                "subscores": {
                    "file_exists": True,
                    "correct_path": False,
                    "has_all_columns": False,
                    "correct_row_count": False,
                    "content_valid": False
                }
            }

        # Criterion 1: File exists at correct path
        criteria_passed += 1
        feedback_parts.append(f"File exists at correct path")

        # CRITICAL CHECK 2: Must have ALL required columns
        columns_present = []
        columns_missing = []

        if has_customerid:
            columns_present.append('CustomerId')
        else:
            columns_missing.append('CustomerId')
        if has_firstname:
            columns_present.append('FirstName')
        else:
            columns_missing.append('FirstName')
        if has_lastname:
            columns_present.append('LastName')
        else:
            columns_missing.append('LastName')
        if has_email:
            columns_present.append('Email')
        else:
            columns_missing.append('Email')

        if len(columns_missing) == 0:
            criteria_passed += 1
            feedback_parts.append(f"All required columns present ({len(columns_present)}/4)")
        else:
            critical_failures.append(f"Missing required columns: {', '.join(columns_missing)}")
            feedback_parts.append(f"MISSING COLUMNS: {', '.join(columns_missing)}")

        # Criterion 3: Correct number of rows (stricter tolerance: ±2)
        row_tolerance = 2
        if abs(row_count - expected_row_count) <= row_tolerance:
            criteria_passed += 1
            feedback_parts.append(f"Row count correct: {row_count} (expected {expected_row_count})")
        elif row_count > 0:
            # Small partial credit if some data
            criteria_passed += 0.3
            feedback_parts.append(f"WRONG ROW COUNT: {row_count} (expected {expected_row_count})")
        else:
            critical_failures.append("File has no data rows")
            feedback_parts.append("NO DATA: File is empty or only has header")

        # CRITICAL CHECK 4: Content must validate as customers data
        # Checks that at least min_customers_required known customer records are present
        if content_valid:
            criteria_passed += 1
            feedback_parts.append(f"Content validated: {customers_matched} known customers found")
        elif customers_matched > 0:
            # Partial credit if some customers matched
            criteria_passed += 0.3
            feedback_parts.append(f"PARTIAL MATCH: Only {customers_matched}/{min_customers_required} customers verified")
            critical_failures.append(f"Only {customers_matched} of {min_customers_required} required customers found")
        else:
            critical_failures.append("No known customer records found in export")
            feedback_parts.append("INVALID CONTENT: No known customers detected")

        # Criterion 5: File was created during task
        if created_recently:
            criteria_passed += 1
            feedback_parts.append("File created during task")
        else:
            # Partial credit
            criteria_passed += 0.5
            feedback_parts.append("File may be pre-existing")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # STRICT PASS REQUIREMENTS:
        # - File must exist at correct path
        # - All required columns must be present
        # - Content must be valid
        # - Row count must be within tolerance
        # - Score >= 80%
        passed = (
            file_exists and
            correct_path and
            len(columns_missing) == 0 and
            content_valid and
            abs(row_count - expected_row_count) <= row_tolerance and
            score >= 80
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL ISSUES: " + "; ".join(critical_failures))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "file_exists": file_exists,
                "correct_path": correct_path,
                "has_all_columns": len(columns_missing) == 0,
                "correct_row_count": abs(row_count - expected_row_count) <= row_tolerance,
                "content_valid": content_valid
            }
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
