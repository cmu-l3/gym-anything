#!/usr/bin/env python3
"""
Verifier for Add Employee task in Oracle Database environment.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_employee(traj, env_info, task_info):
    """
    Verify that the expected employee was added to the Oracle HR database.

    The expected employee details are read from task_info metadata.
    Defaults: Sarah Johnson, IT Programmer, Salary 5500, Department 60

    Checks:
    1. Employee with expected first_name and last_name exists in database
    2. Employee email matches expected value (SJOHNSON)
    3. Employee job_id matches expected value (IT_PROG)
    4. Employee salary matches expected value (5500)
    5. Employee department_id matches expected value (60)
    6. Employee was created during this session (id > initial max)
    7. Employee phone matches expected value (650.555.1234)
    8. Employee manager_id matches expected value (103)
    9. Employee hire_date is a valid date in 2024
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_first_name', 'Sarah')
    expected_lname = metadata.get('expected_last_name', 'Johnson')
    expected_email = metadata.get('expected_email', 'SJOHNSON')
    expected_job_id = metadata.get('expected_job_id', 'IT_PROG')
    expected_salary = metadata.get('expected_salary', 5500)
    expected_dept_id = metadata.get('expected_department_id', 60)
    expected_phone = metadata.get('expected_phone', '650.555.1234')
    expected_manager_id = metadata.get('expected_manager_id', 103)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_employee_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 9  # Updated to include phone, manager_id, hire_date
        feedback_parts = []

        initial_count = result.get('initial_employee_count', 0)
        current_count = result.get('current_employee_count', 0)
        initial_max_id = result.get('initial_max_id', 0)
        current_max_id = result.get('current_max_id', 0)
        employee_found = result.get('employee_found', False)
        employee = result.get('employee', {})

        logger.info(f"Result data: initial_count={initial_count}, current_count={current_count}")
        logger.info(f"Employee data: {employee}")

        # Criterion 1: Check if employee exists with expected name
        if employee_found:
            fname = employee.get('first_name', '')
            lname = employee.get('last_name', '')

            if fname.lower() == expected_fname.lower() and lname.lower() == expected_lname.lower():
                criteria_passed += 1
                feedback_parts.append(f"Employee '{expected_fname} {expected_lname}' found in database")
            else:
                feedback_parts.append(f"Employee name mismatch: expected '{expected_fname} {expected_lname}', got '{fname} {lname}'")
        else:
            feedback_parts.append(f"Employee '{expected_fname} {expected_lname}' NOT found in database")

            # Check if any new employees were added at all
            if current_count > initial_count:
                new_employees = current_count - initial_count
                feedback_parts.append(f"Note: {new_employees} new employee(s) added, but not with expected name")
            else:
                feedback_parts.append("No new employees were added to the database")

            # Early return since no employee found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "employee_exists": False,
                    "email_correct": False,
                    "job_correct": False,
                    "salary_correct": False,
                    "department_correct": False,
                    "newly_added": False,
                    "phone_correct": False,
                    "manager_correct": False,
                    "hire_date_correct": False
                }
            }

        # Criterion 2: Check email
        email = employee.get('email', '').upper()
        if email == expected_email.upper():
            criteria_passed += 1
            feedback_parts.append(f"Email correct: {expected_email}")
        else:
            feedback_parts.append(f"Email incorrect: expected {expected_email}, got {email}")

        # Criterion 3: Check job_id
        job_id = employee.get('job_id', '').upper()
        if job_id == expected_job_id.upper():
            criteria_passed += 1
            feedback_parts.append(f"Job correct: {expected_job_id}")
        else:
            feedback_parts.append(f"Job incorrect: expected {expected_job_id}, got {job_id}")

        # Criterion 4: Check salary
        try:
            salary = float(employee.get('salary', 0))
            if abs(salary - expected_salary) < 1:  # Allow for floating point
                criteria_passed += 1
                feedback_parts.append(f"Salary correct: {expected_salary}")
            else:
                feedback_parts.append(f"Salary incorrect: expected {expected_salary}, got {salary}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not parse salary: {employee.get('salary')}")

        # Criterion 5: Check department_id
        try:
            dept_id = int(employee.get('department_id', 0))
            if dept_id == expected_dept_id:
                criteria_passed += 1
                feedback_parts.append(f"Department correct: {expected_dept_id}")
            else:
                feedback_parts.append(f"Department incorrect: expected {expected_dept_id}, got {dept_id}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not parse department_id: {employee.get('department_id')}")

        # Criterion 6: Check if employee was newly added (id > initial max)
        # NO partial credit - this is an anti-cheat check
        try:
            emp_id = int(employee.get('employee_id', 0))
            if emp_id > initial_max_id:
                criteria_passed += 1
                feedback_parts.append(f"Employee newly added with ID={emp_id} (initial max was {initial_max_id})")
            else:
                # No partial credit for existing employees - this is likely cheating
                feedback_parts.append(f"FAIL: Employee existed before task (ID={emp_id} <= initial_max={initial_max_id})")
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not verify employee ID: {employee.get('employee_id')}")

        # Criterion 7: Check phone number
        phone = employee.get('phone_number', '')
        if phone and phone != 'N/A':
            # Normalize phone for comparison (remove spaces, compare digits)
            phone_digits = ''.join(c for c in phone if c.isdigit() or c == '.')
            expected_phone_digits = ''.join(c for c in expected_phone if c.isdigit() or c == '.')
            if phone_digits == expected_phone_digits:
                criteria_passed += 1
                feedback_parts.append(f"Phone correct: {expected_phone}")
            else:
                feedback_parts.append(f"Phone incorrect: expected {expected_phone}, got {phone}")
        else:
            feedback_parts.append(f"Phone not set (expected {expected_phone})")

        # Criterion 8: Check manager_id
        try:
            mgr_id = employee.get('manager_id', '')
            if mgr_id and mgr_id != 'N/A':
                mgr_id_int = int(mgr_id)
                if mgr_id_int == expected_manager_id:
                    criteria_passed += 1
                    feedback_parts.append(f"Manager correct: {expected_manager_id}")
                else:
                    feedback_parts.append(f"Manager incorrect: expected {expected_manager_id}, got {mgr_id_int}")
            else:
                feedback_parts.append(f"Manager not set (expected {expected_manager_id})")
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not parse manager_id: {employee.get('manager_id')}")

        # Criterion 9: Check hire_date (must be January 15, 2024 - no partial credit)
        # Use regex with anchors to prevent substring matching (e.g., "2024-01-150" should not match)
        hire_date = employee.get('hire_date', '')
        if hire_date and hire_date != 'N/A':
            hire_date_clean = hire_date.strip().upper()
            # Regex patterns with word boundaries/anchors to match exact dates only
            date_patterns = [
                r'^2024-01-15$',           # ISO format exact
                r'\b2024-01-15\b',          # ISO format with word boundaries
                r'^15-JAN-24$',             # Oracle short format exact
                r'\b15-JAN-24\b',           # Oracle short format with word boundaries
                r'^15-JAN-2024$',           # Oracle long format exact
                r'\b15-JAN-2024\b',         # Oracle long format with word boundaries
                r'^15-01-2024$',            # European format exact
                r'\b15-01-2024\b',          # European format with word boundaries
                r'^01-15-2024$',            # US format with dashes exact
                r'\b01-15-2024\b',          # US format with dashes
                r'^01/15/2024$',            # US format with slashes exact
                r'\b01/15/2024\b',          # US format with slashes
            ]
            is_correct_date = any(re.search(pattern, hire_date_clean, re.IGNORECASE) for pattern in date_patterns)
            if is_correct_date:
                criteria_passed += 1
                feedback_parts.append(f"Hire date correct: {hire_date}")
            else:
                # No partial credit - wrong date is wrong
                feedback_parts.append(f"Hire date incorrect: expected January 15, 2024, got {hire_date}")
        else:
            feedback_parts.append("Hire date not set (expected January 15, 2024)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # Check critical criteria - these MUST pass for overall pass
        # 1. Name must be correct (Sarah Johnson)
        name_correct = (employee.get('first_name', '').lower() == expected_fname.lower() and
                       employee.get('last_name', '').lower() == expected_lname.lower())
        # 2. Employee must be newly added (anti-cheat)
        try:
            emp_id_val = int(employee.get('employee_id', 0))
            newly_added = emp_id_val > initial_max_id
        except (ValueError, TypeError):
            newly_added = False

        # Pass requires: score >= 78% (7/9) AND critical criteria met
        passed = score >= 78 and name_correct and newly_added

        feedback = " | ".join(feedback_parts)

        # Build subscores dictionary
        subscores = {
            "employee_exists": employee_found,
            "email_correct": email == expected_email.upper(),
            "job_correct": job_id == expected_job_id.upper(),
            "salary_correct": False,
            "department_correct": False,
            "newly_added": False,
            "phone_correct": False,
            "manager_correct": False,
            "hire_date_correct": False
        }

        # Safely evaluate subscores
        try:
            subscores["salary_correct"] = abs(float(employee.get('salary', 0)) - expected_salary) < 1 if employee.get('salary') else False
        except (ValueError, TypeError):
            pass

        try:
            subscores["department_correct"] = int(employee.get('department_id', 0)) == expected_dept_id if employee.get('department_id') else False
        except (ValueError, TypeError):
            pass

        try:
            subscores["newly_added"] = int(employee.get('employee_id', 0)) > initial_max_id if employee.get('employee_id') else False
        except (ValueError, TypeError):
            pass

        try:
            phone_val = employee.get('phone_number', '')
            if phone_val and phone_val != 'N/A':
                phone_digits = ''.join(c for c in phone_val if c.isdigit() or c == '.')
                expected_phone_digits = ''.join(c for c in expected_phone if c.isdigit() or c == '.')
                subscores["phone_correct"] = phone_digits == expected_phone_digits
        except (ValueError, TypeError):
            pass

        try:
            mgr_val = employee.get('manager_id', '')
            if mgr_val and mgr_val != 'N/A':
                subscores["manager_correct"] = int(mgr_val) == expected_manager_id
        except (ValueError, TypeError):
            pass

        try:
            hire_val = employee.get('hire_date', '')
            if hire_val and hire_val != 'N/A':
                hire_clean = hire_val.strip().upper()
                # Use same regex patterns as main validation
                date_patterns = [
                    r'^2024-01-15$', r'\b2024-01-15\b',
                    r'^15-JAN-24$', r'\b15-JAN-24\b',
                    r'^15-JAN-2024$', r'\b15-JAN-2024\b',
                    r'^15-01-2024$', r'\b15-01-2024\b',
                    r'^01-15-2024$', r'\b01-15-2024\b',
                    r'^01/15/2024$', r'\b01/15/2024\b',
                ]
                subscores["hire_date_correct"] = any(
                    re.search(pattern, hire_clean, re.IGNORECASE) for pattern in date_patterns
                )
        except (ValueError, TypeError):
            pass

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
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
