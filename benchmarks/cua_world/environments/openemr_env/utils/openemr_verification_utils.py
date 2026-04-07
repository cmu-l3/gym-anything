#!/usr/bin/env python3
"""
OpenEMR verification utilities for gym-anything tasks
Provides helper functions to verify OpenEMR tasks using database queries
"""

import logging
from typing import Dict, List, Any, Optional, Callable

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database credentials (must match docker-compose.yml)
DB_USER = "openemr"
DB_PASS = "openemr"
DB_NAME = "openemr"
DOCKER_CONTAINER = "openemr-mysql"


def query_database(exec_in_env: Callable, query: str) -> str:
    """
    Execute a SQL query against the OpenEMR database via Docker container.

    Args:
        exec_in_env: Function to execute commands in the VM
        query: SQL query to execute

    Returns:
        Query result as string
    """
    # Escape single quotes in query
    safe_query = query.replace("'", "'\\''")
    # Execute via Docker container
    cmd = f"docker exec {DOCKER_CONTAINER} mysql -u {DB_USER} -p{DB_PASS} {DB_NAME} -N -e '{safe_query}' 2>/dev/null"

    try:
        result = exec_in_env(cmd)
        return result.strip() if result else ""
    except Exception as e:
        logger.error(f"Database query failed: {e}")
        return ""


def get_patient_count(exec_in_env: Callable) -> int:
    """
    Get the total number of patients in the database.

    Args:
        exec_in_env: Function to execute commands in the container

    Returns:
        Patient count
    """
    result = query_database(exec_in_env, "SELECT COUNT(*) FROM patient_data")
    try:
        return int(result) if result else 0
    except ValueError:
        return 0


def find_patient_by_name(exec_in_env: Callable, fname: str, lname: str) -> Optional[Dict[str, Any]]:
    """
    Search for a patient by first and last name.

    Args:
        exec_in_env: Function to execute commands in the container
        fname: First name to search for
        lname: Last name to search for

    Returns:
        Dictionary with patient data or None if not found
    """
    query = f"""
        SELECT pid, fname, lname, DOB, sex, street, city, state, postal_code, phone_cell, email
        FROM patient_data
        WHERE fname='{fname}' AND lname='{lname}'
        LIMIT 1
    """
    result = query_database(exec_in_env, query)

    if not result:
        return None

    # Parse tab-separated result
    fields = result.split('\t')
    if len(fields) >= 5:
        return {
            'pid': fields[0],
            'fname': fields[1],
            'lname': fields[2],
            'DOB': fields[3],
            'sex': fields[4],
            'street': fields[5] if len(fields) > 5 else '',
            'city': fields[6] if len(fields) > 6 else '',
            'state': fields[7] if len(fields) > 7 else '',
            'postal_code': fields[8] if len(fields) > 8 else '',
            'phone_cell': fields[9] if len(fields) > 9 else '',
            'email': fields[10] if len(fields) > 10 else ''
        }

    return None


def find_patient_by_id(exec_in_env: Callable, pid: int) -> Optional[Dict[str, Any]]:
    """
    Search for a patient by patient ID.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID

    Returns:
        Dictionary with patient data or None if not found
    """
    query = f"""
        SELECT pid, fname, lname, DOB, sex, street, city, state, postal_code, phone_cell, email
        FROM patient_data
        WHERE pid={pid}
        LIMIT 1
    """
    result = query_database(exec_in_env, query)

    if not result:
        return None

    fields = result.split('\t')
    if len(fields) >= 5:
        return {
            'pid': fields[0],
            'fname': fields[1],
            'lname': fields[2],
            'DOB': fields[3],
            'sex': fields[4],
            'street': fields[5] if len(fields) > 5 else '',
            'city': fields[6] if len(fields) > 6 else '',
            'state': fields[7] if len(fields) > 7 else '',
            'postal_code': fields[8] if len(fields) > 8 else '',
            'phone_cell': fields[9] if len(fields) > 9 else '',
            'email': fields[10] if len(fields) > 10 else ''
        }

    return None


def verify_patient_details(exec_in_env: Callable, fname: str, lname: str,
                          expected_dob: str = None, expected_sex: str = None) -> Dict[str, Any]:
    """
    Verify patient details match expected values.

    Args:
        exec_in_env: Function to execute commands in the container
        fname: Expected first name
        lname: Expected last name
        expected_dob: Expected date of birth (YYYY-MM-DD format)
        expected_sex: Expected sex (Male/Female)

    Returns:
        Dictionary with verification results
    """
    patient = find_patient_by_name(exec_in_env, fname, lname)

    result = {
        'found': patient is not None,
        'name_match': False,
        'dob_match': False,
        'sex_match': False,
        'patient': patient
    }

    if not patient:
        return result

    result['name_match'] = (
        patient.get('fname', '').lower() == fname.lower() and
        patient.get('lname', '').lower() == lname.lower()
    )

    if expected_dob:
        result['dob_match'] = patient.get('DOB', '') == expected_dob

    if expected_sex:
        actual_sex = patient.get('sex', '').lower()
        expected_sex_lower = expected_sex.lower()
        result['sex_match'] = (
            actual_sex == expected_sex_lower or
            (actual_sex == 'm' and expected_sex_lower == 'male') or
            (actual_sex == 'f' and expected_sex_lower == 'female')
        )

    return result


def get_appointments_for_patient(exec_in_env: Callable, pid: int) -> List[Dict[str, Any]]:
    """
    Get appointments for a specific patient.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID

    Returns:
        List of appointment dictionaries
    """
    query = f"""
        SELECT pc_eid, pc_catid, pc_title, pc_eventDate, pc_startTime, pc_endTime, pc_duration
        FROM openemr_postcalendar_events
        WHERE pc_pid={pid}
        ORDER BY pc_eventDate DESC, pc_startTime DESC
    """
    result = query_database(exec_in_env, query)

    appointments = []
    if result:
        for line in result.strip().split('\n'):
            fields = line.split('\t')
            if len(fields) >= 7:
                appointments.append({
                    'eid': fields[0],
                    'category_id': fields[1],
                    'title': fields[2],
                    'date': fields[3],
                    'start_time': fields[4],
                    'end_time': fields[5],
                    'duration': fields[6]
                })

    return appointments


def get_prescriptions_for_patient(exec_in_env: Callable, pid: int) -> List[Dict[str, Any]]:
    """
    Get prescriptions for a specific patient.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID

    Returns:
        List of prescription dictionaries
    """
    query = f"""
        SELECT id, drug, dosage, quantity, refills, date_added
        FROM prescriptions
        WHERE patient_id={pid}
        ORDER BY date_added DESC
    """
    result = query_database(exec_in_env, query)

    prescriptions = []
    if result:
        for line in result.strip().split('\n'):
            fields = line.split('\t')
            if len(fields) >= 6:
                prescriptions.append({
                    'id': fields[0],
                    'drug': fields[1],
                    'dosage': fields[2],
                    'quantity': fields[3],
                    'refills': fields[4],
                    'date_added': fields[5]
                })

    return prescriptions


def get_encounters_for_patient(exec_in_env: Callable, pid: int) -> List[Dict[str, Any]]:
    """
    Get clinical encounters for a specific patient.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID

    Returns:
        List of encounter dictionaries
    """
    query = f"""
        SELECT id, date, reason, facility_id, provider_id, sensitivity, pc_catid
        FROM form_encounter
        WHERE pid={pid}
        ORDER BY date DESC
    """
    result = query_database(exec_in_env, query)

    encounters = []
    if result:
        for line in result.strip().split('\n'):
            fields = line.split('\t')
            if len(fields) >= 7:
                encounters.append({
                    'id': fields[0],
                    'date': fields[1],
                    'reason': fields[2],
                    'facility_id': fields[3],
                    'provider_id': fields[4],
                    'sensitivity': fields[5],
                    'category_id': fields[6]
                })

    return encounters


def get_user_by_username(exec_in_env: Callable, username: str) -> Optional[Dict[str, Any]]:
    """
    Get user details by username.

    Args:
        exec_in_env: Function to execute commands in the container
        username: Username to search for

    Returns:
        Dictionary with user data or None if not found
    """
    query = f"""
        SELECT id, username, fname, lname, authorized, active, facility_id
        FROM users
        WHERE username='{username}'
        LIMIT 1
    """
    result = query_database(exec_in_env, query)

    if not result:
        return None

    fields = result.split('\t')
    if len(fields) >= 7:
        return {
            'id': fields[0],
            'username': fields[1],
            'fname': fields[2],
            'lname': fields[3],
            'authorized': fields[4] == '1',
            'active': fields[5] == '1',
            'facility_id': fields[6]
        }

    return None


def verify_appointment_exists(exec_in_env: Callable, pid: int, date: str,
                              start_time: str = None) -> bool:
    """
    Verify that an appointment exists for a patient on a specific date.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID
        date: Appointment date (YYYY-MM-DD format)
        start_time: Optional start time (HH:MM:SS format)

    Returns:
        True if appointment exists, False otherwise
    """
    if start_time:
        query = f"""
            SELECT COUNT(*) FROM openemr_postcalendar_events
            WHERE pc_pid={pid} AND pc_eventDate='{date}' AND pc_startTime='{start_time}'
        """
    else:
        query = f"""
            SELECT COUNT(*) FROM openemr_postcalendar_events
            WHERE pc_pid={pid} AND pc_eventDate='{date}'
        """

    result = query_database(exec_in_env, query)
    try:
        return int(result) > 0
    except ValueError:
        return False


def verify_prescription_exists(exec_in_env: Callable, pid: int, drug: str) -> bool:
    """
    Verify that a prescription exists for a patient.

    Args:
        exec_in_env: Function to execute commands in the container
        pid: Patient ID
        drug: Drug name to search for

    Returns:
        True if prescription exists, False otherwise
    """
    query = f"""
        SELECT COUNT(*) FROM prescriptions
        WHERE patient_id={pid} AND drug LIKE '%{drug}%'
    """
    result = query_database(exec_in_env, query)
    try:
        return int(result) > 0
    except ValueError:
        return False


def list_recent_patients(exec_in_env: Callable, limit: int = 10) -> List[Dict[str, Any]]:
    """
    List the most recently added patients.

    Args:
        exec_in_env: Function to execute commands in the container
        limit: Maximum number of patients to return

    Returns:
        List of patient dictionaries
    """
    query = f"""
        SELECT pid, fname, lname, DOB, sex, create_date
        FROM patient_data
        ORDER BY pid DESC
        LIMIT {limit}
    """
    result = query_database(exec_in_env, query)

    patients = []
    if result:
        for line in result.strip().split('\n'):
            fields = line.split('\t')
            if len(fields) >= 5:
                patients.append({
                    'pid': fields[0],
                    'fname': fields[1],
                    'lname': fields[2],
                    'DOB': fields[3],
                    'sex': fields[4],
                    'create_date': fields[5] if len(fields) > 5 else ''
                })

    return patients
