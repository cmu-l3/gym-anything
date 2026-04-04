"""
OpenSIS Database Verification Utilities

This module provides functions to verify OpenSIS tasks via MySQL database queries.
Uses exec_in_env from env_info to execute commands inside the container.

Usage:
    from opensis_verification_utils import verify_student_exists, run_mysql_query

Environment Variables (in container):
    OPENSIS_DB_USER: Database username (default: opensis_user)
    OPENSIS_DB_PASS: Database password (default: opensis_password_123)
    OPENSIS_DB_NAME: Database name (default: opensis)
"""

import os
import re
import json
import logging
from typing import Dict, Any, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database credentials (matching setup_opensis.sh)
DEFAULT_DB_USER = "opensis_user"
DEFAULT_DB_PASS = "opensis_password_123"
DEFAULT_DB_NAME = "opensis"


# =============================================================================
# MYSQL QUERY EXECUTION
# =============================================================================

def run_mysql_query(
    exec_in_env: callable,
    query: str,
    db_user: str = DEFAULT_DB_USER,
    db_pass: str = DEFAULT_DB_PASS,
    db_name: str = DEFAULT_DB_NAME,
) -> Tuple[bool, str]:
    """
    Execute a MySQL query in the container and return results.

    Args:
        exec_in_env: Function to execute commands in container (from env_info)
        query: SQL query to execute
        db_user: Database username
        db_pass: Database password
        db_name: Database name

    Returns:
        Tuple of (success: bool, output: str)
    """
    # Escape single quotes in query
    escaped_query = query.replace("'", "\\'")

    # Build mysql command
    cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -e \"{escaped_query}\" 2>/dev/null"

    try:
        result = exec_in_env(cmd)
        return (True, result.strip() if result else "")
    except Exception as e:
        logger.error(f"MySQL query failed: {e}")
        return (False, str(e))


def run_mysql_query_json(
    exec_in_env: callable,
    query: str,
    db_user: str = DEFAULT_DB_USER,
    db_pass: str = DEFAULT_DB_PASS,
    db_name: str = DEFAULT_DB_NAME,
) -> Tuple[bool, List[Dict[str, Any]]]:
    """
    Execute a MySQL query and return results as JSON-like list of dicts.

    Args:
        exec_in_env: Function to execute commands in container
        query: SQL query to execute
        db_user: Database username
        db_pass: Database password
        db_name: Database name

    Returns:
        Tuple of (success: bool, rows: List[Dict])
    """
    # Use tab-separated output for easier parsing
    escaped_query = query.replace("'", "\\'")
    cmd = f"mysql -u {db_user} -p'{db_pass}' {db_name} -N -B -e \"{escaped_query}\" 2>/dev/null"

    try:
        result = exec_in_env(cmd)
        if not result or not result.strip():
            return (True, [])

        # Parse tab-separated output
        lines = result.strip().split('\n')
        rows = []
        for line in lines:
            if line.strip():
                cols = line.split('\t')
                rows.append(cols)
        return (True, rows)
    except Exception as e:
        logger.error(f"MySQL query failed: {e}")
        return (False, [])


# =============================================================================
# STUDENT VERIFICATION
# =============================================================================

def verify_student_exists(
    exec_in_env: callable,
    first_name: str,
    last_name: str,
    **kwargs,
) -> Dict[str, Any]:
    """
    Verify a student record exists in the database.

    Args:
        exec_in_env: Function to execute commands in container
        first_name: Student's first name
        last_name: Student's last name
        **kwargs: Additional fields to verify (date_of_birth, gender, etc.)

    Returns:
        Dict with 'found' (bool), 'student_id' (int or None), 'record' (dict or None)
    """
    # Build WHERE clause
    conditions = [
        f"first_name = '{first_name}'",
        f"last_name = '{last_name}'",
    ]

    for field, value in kwargs.items():
        if value is not None:
            conditions.append(f"{field} = '{value}'")

    where_clause = " AND ".join(conditions)
    query = f"SELECT student_id, first_name, last_name, date_of_birth, gender, email, grade_level FROM students WHERE {where_clause} LIMIT 1"

    success, output = run_mysql_query(exec_in_env, query)

    if not success:
        return {"found": False, "student_id": None, "record": None, "error": output}

    # Parse output (tab-separated, first line is header)
    lines = output.strip().split('\n')
    if len(lines) < 2:
        return {"found": False, "student_id": None, "record": None}

    # Header and data
    headers = lines[0].split('\t')
    values = lines[1].split('\t')

    if len(headers) != len(values):
        return {"found": False, "student_id": None, "record": None}

    record = dict(zip(headers, values))

    return {
        "found": True,
        "student_id": int(record.get("student_id", 0)),
        "record": record,
    }


def get_student_by_name(
    exec_in_env: callable,
    first_name: str = None,
    last_name: str = None,
) -> List[Dict[str, Any]]:
    """
    Search for students by name (partial match).

    Args:
        exec_in_env: Function to execute commands in container
        first_name: First name to search (partial match)
        last_name: Last name to search (partial match)

    Returns:
        List of matching student records
    """
    conditions = []
    if first_name:
        conditions.append(f"first_name LIKE '%{first_name}%'")
    if last_name:
        conditions.append(f"last_name LIKE '%{last_name}%'")

    if not conditions:
        return []

    where_clause = " AND ".join(conditions)
    query = f"SELECT student_id, first_name, last_name, date_of_birth, grade_level FROM students WHERE {where_clause}"

    success, output = run_mysql_query(exec_in_env, query)

    if not success or not output.strip():
        return []

    # Parse output
    lines = output.strip().split('\n')
    if len(lines) < 2:
        return []

    headers = lines[0].split('\t')
    students = []
    for line in lines[1:]:
        if line.strip():
            values = line.split('\t')
            if len(headers) == len(values):
                students.append(dict(zip(headers, values)))

    return students


# =============================================================================
# COURSE VERIFICATION
# =============================================================================

def verify_course_exists(
    exec_in_env: callable,
    course_name: str = None,
    course_code: str = None,
    **kwargs,
) -> Dict[str, Any]:
    """
    Verify a course record exists in the database.

    Args:
        exec_in_env: Function to execute commands in container
        course_name: Course name (partial match)
        course_code: Course code (exact match)
        **kwargs: Additional fields to verify

    Returns:
        Dict with 'found' (bool), 'course_id' (int or None), 'record' (dict or None)
    """
    conditions = []
    if course_name:
        conditions.append(f"course_name LIKE '%{course_name}%'")
    if course_code:
        conditions.append(f"course_code = '{course_code}'")

    for field, value in kwargs.items():
        if value is not None:
            conditions.append(f"{field} = '{value}'")

    if not conditions:
        return {"found": False, "course_id": None, "record": None, "error": "No search criteria provided"}

    where_clause = " AND ".join(conditions)
    query = f"SELECT course_id, course_name, course_code, subject_area, grade_level, credits FROM courses WHERE {where_clause} LIMIT 1"

    success, output = run_mysql_query(exec_in_env, query)

    if not success:
        return {"found": False, "course_id": None, "record": None, "error": output}

    # Parse output
    lines = output.strip().split('\n')
    if len(lines) < 2:
        return {"found": False, "course_id": None, "record": None}

    headers = lines[0].split('\t')
    values = lines[1].split('\t')

    if len(headers) != len(values):
        return {"found": False, "course_id": None, "record": None}

    record = dict(zip(headers, values))

    return {
        "found": True,
        "course_id": int(record.get("course_id", 0)),
        "record": record,
    }


def get_course_by_name(
    exec_in_env: callable,
    course_name: str,
) -> List[Dict[str, Any]]:
    """
    Search for courses by name (partial match).

    Args:
        exec_in_env: Function to execute commands in container
        course_name: Course name to search

    Returns:
        List of matching course records
    """
    query = f"SELECT course_id, course_name, course_code, subject_area FROM courses WHERE course_name LIKE '%{course_name}%'"

    success, output = run_mysql_query(exec_in_env, query)

    if not success or not output.strip():
        return []

    lines = output.strip().split('\n')
    if len(lines) < 2:
        return []

    headers = lines[0].split('\t')
    courses = []
    for line in lines[1:]:
        if line.strip():
            values = line.split('\t')
            if len(headers) == len(values):
                courses.append(dict(zip(headers, values)))

    return courses


# =============================================================================
# ATTENDANCE VERIFICATION
# =============================================================================

def verify_attendance_recorded(
    exec_in_env: callable,
    student_id: int = None,
    student_first_name: str = None,
    student_last_name: str = None,
    attendance_date: str = None,
    status: str = None,
) -> Dict[str, Any]:
    """
    Verify an attendance record exists.

    Args:
        exec_in_env: Function to execute commands in container
        student_id: Student ID (if known)
        student_first_name: Student first name (for lookup)
        student_last_name: Student last name (for lookup)
        attendance_date: Date in YYYY-MM-DD format
        status: Expected status (present, absent, late, excused)

    Returns:
        Dict with 'found' (bool), 'attendance_id' (int or None), 'record' (dict or None)
    """
    # If student name provided, look up ID first
    if not student_id and (student_first_name or student_last_name):
        student_result = verify_student_exists(
            exec_in_env,
            first_name=student_first_name or "",
            last_name=student_last_name or "",
        )
        if student_result.get("found"):
            student_id = student_result["student_id"]
        else:
            return {"found": False, "attendance_id": None, "record": None, "error": "Student not found"}

    conditions = []
    if student_id:
        conditions.append(f"student_id = {student_id}")
    if attendance_date:
        conditions.append(f"attendance_date = '{attendance_date}'")
    if status:
        conditions.append(f"status = '{status}'")

    if not conditions:
        return {"found": False, "attendance_id": None, "record": None, "error": "No search criteria"}

    where_clause = " AND ".join(conditions)
    query = f"SELECT attendance_id, student_id, attendance_date, status, notes FROM attendance WHERE {where_clause} LIMIT 1"

    success, output = run_mysql_query(exec_in_env, query)

    if not success:
        return {"found": False, "attendance_id": None, "record": None, "error": output}

    lines = output.strip().split('\n')
    if len(lines) < 2:
        return {"found": False, "attendance_id": None, "record": None}

    headers = lines[0].split('\t')
    values = lines[1].split('\t')

    if len(headers) != len(values):
        return {"found": False, "attendance_id": None, "record": None}

    record = dict(zip(headers, values))

    return {
        "found": True,
        "attendance_id": int(record.get("attendance_id", 0)),
        "record": record,
    }


# =============================================================================
# GRADE VERIFICATION
# =============================================================================

def verify_grade_recorded(
    exec_in_env: callable,
    student_id: int = None,
    student_first_name: str = None,
    student_last_name: str = None,
    course_id: int = None,
    course_name: str = None,
    assignment_name: str = None,
    grade_value: float = None,
) -> Dict[str, Any]:
    """
    Verify a grade record exists.

    Args:
        exec_in_env: Function to execute commands in container
        student_id: Student ID (if known)
        student_first_name: Student first name (for lookup)
        student_last_name: Student last name (for lookup)
        course_id: Course ID (if known)
        course_name: Course name (for lookup)
        assignment_name: Assignment name
        grade_value: Expected grade value

    Returns:
        Dict with 'found' (bool), 'grade_id' (int or None), 'record' (dict or None)
    """
    # Look up student ID if name provided
    if not student_id and (student_first_name or student_last_name):
        student_result = verify_student_exists(
            exec_in_env,
            first_name=student_first_name or "",
            last_name=student_last_name or "",
        )
        if student_result.get("found"):
            student_id = student_result["student_id"]
        else:
            return {"found": False, "grade_id": None, "record": None, "error": "Student not found"}

    # Look up course ID if name provided
    if not course_id and course_name:
        course_result = verify_course_exists(exec_in_env, course_name=course_name)
        if course_result.get("found"):
            course_id = course_result["course_id"]
        else:
            return {"found": False, "grade_id": None, "record": None, "error": "Course not found"}

    conditions = []
    if student_id:
        conditions.append(f"student_id = {student_id}")
    if course_id:
        conditions.append(f"course_id = {course_id}")
    if assignment_name:
        conditions.append(f"assignment_name LIKE '%{assignment_name}%'")
    if grade_value is not None:
        conditions.append(f"grade_value = {grade_value}")

    if not conditions:
        return {"found": False, "grade_id": None, "record": None, "error": "No search criteria"}

    where_clause = " AND ".join(conditions)
    query = f"SELECT grade_id, student_id, course_id, assignment_name, grade_value, grade_letter FROM grades WHERE {where_clause} LIMIT 1"

    success, output = run_mysql_query(exec_in_env, query)

    if not success:
        return {"found": False, "grade_id": None, "record": None, "error": output}

    lines = output.strip().split('\n')
    if len(lines) < 2:
        return {"found": False, "grade_id": None, "record": None}

    headers = lines[0].split('\t')
    values = lines[1].split('\t')

    if len(headers) != len(values):
        return {"found": False, "grade_id": None, "record": None}

    record = dict(zip(headers, values))

    return {
        "found": True,
        "grade_id": int(record.get("grade_id", 0)),
        "record": record,
    }


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def count_table_rows(
    exec_in_env: callable,
    table_name: str,
    where_clause: str = None,
) -> int:
    """
    Count rows in a table.

    Args:
        exec_in_env: Function to execute commands in container
        table_name: Table name
        where_clause: Optional WHERE clause

    Returns:
        Row count (0 if query fails)
    """
    query = f"SELECT COUNT(*) FROM {table_name}"
    if where_clause:
        query += f" WHERE {where_clause}"

    success, output = run_mysql_query(exec_in_env, query)

    if not success:
        return 0

    try:
        # Output format: header line + count line
        lines = output.strip().split('\n')
        if len(lines) >= 2:
            return int(lines[1].strip())
        return 0
    except (ValueError, IndexError):
        return 0


def get_latest_record(
    exec_in_env: callable,
    table_name: str,
    id_column: str = "id",
) -> Optional[Dict[str, Any]]:
    """
    Get the most recently inserted record from a table.

    Args:
        exec_in_env: Function to execute commands in container
        table_name: Table name
        id_column: Name of the auto-increment ID column

    Returns:
        Record dict or None
    """
    query = f"SELECT * FROM {table_name} ORDER BY {id_column} DESC LIMIT 1"

    success, output = run_mysql_query(exec_in_env, query)

    if not success or not output.strip():
        return None

    lines = output.strip().split('\n')
    if len(lines) < 2:
        return None

    headers = lines[0].split('\t')
    values = lines[1].split('\t')

    if len(headers) != len(values):
        return None

    return dict(zip(headers, values))
