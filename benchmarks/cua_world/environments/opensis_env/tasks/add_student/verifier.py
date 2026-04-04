"""
Verifier for add_student task.

Task: Add a new student to OpenSIS with:
    - First name: Emily
    - Last name: Johnson
    - Date of birth: 2008-03-15
    - Gender: Female
    - Grade level: 10

Verification Strategy:
1. PRIMARY: Query MySQL database to verify student record exists
2. FALLBACK: Use VLM to check for success message in UI
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected student data
EXPECTED_STUDENT = {
    "first_name": "Emily",
    "last_name": "Johnson",
    "date_of_birth": "2008-03-15",
    "gender": "F",  # Database stores M/F
    "grade_level": "10",
}


# =============================================================================
# DATABASE VERIFICATION
# =============================================================================

def verify_student_in_database(exec_in_env: callable) -> Dict[str, Any]:
    """
    Query MySQL to verify student record exists.

    Args:
        exec_in_env: Function to execute commands in container

    Returns:
        Dict with 'found', 'record', 'error'
    """
    try:
        # Query for the expected student
        query = f"""SELECT student_id, first_name, last_name, date_of_birth, gender, grade_level
                    FROM students
                    WHERE first_name = '{EXPECTED_STUDENT["first_name"]}'
                    AND last_name = '{EXPECTED_STUDENT["last_name"]}'"""

        cmd = f"mysql -u opensis_user -p'opensis_password_123' opensis -e \"{query}\" 2>/dev/null"
        result = exec_in_env(cmd)

        if not result or not result.strip():
            return {"found": False, "record": None, "error": None}

        # Parse output (tab-separated, first line is header)
        lines = result.strip().split('\n')
        if len(lines) < 2:
            return {"found": False, "record": None, "error": None}

        headers = lines[0].split('\t')
        values = lines[1].split('\t')

        if len(headers) != len(values):
            return {"found": False, "record": None, "error": "Parse error"}

        record = dict(zip(headers, values))
        return {"found": True, "record": record, "error": None}

    except Exception as e:
        logger.error(f"Database query failed: {e}")
        return {"found": False, "record": None, "error": str(e)}


def verify_student_fields(record: Dict[str, str]) -> Dict[str, bool]:
    """
    Verify that student record fields match expected values.

    Args:
        record: Student record from database

    Returns:
        Dict with field verification results
    """
    results = {}

    # First name
    results["first_name"] = record.get("first_name", "").lower() == EXPECTED_STUDENT["first_name"].lower()

    # Last name
    results["last_name"] = record.get("last_name", "").lower() == EXPECTED_STUDENT["last_name"].lower()

    # Date of birth (flexible matching)
    dob = record.get("date_of_birth", "")
    results["date_of_birth"] = EXPECTED_STUDENT["date_of_birth"] in dob or dob == EXPECTED_STUDENT["date_of_birth"]

    # Gender (may be stored as 'M', 'F', 'Male', 'Female')
    gender = record.get("gender", "").upper()
    results["gender"] = gender in ("F", "FEMALE", "2")

    # Grade level
    grade = record.get("grade_level", "")
    results["grade_level"] = EXPECTED_STUDENT["grade_level"] in grade or grade == EXPECTED_STUDENT["grade_level"]

    return results


# =============================================================================
# VLM VERIFICATION (FALLBACK)
# =============================================================================

VLM_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully added a new student record in OpenSIS (Student Information System).

TASK: Add a student named Emily Johnson to the system.

Look at this screenshot and determine:
1. Is this OpenSIS or a Student Information System interface?
2. Is there a success message indicating a student was added/created?
3. Can you see the student name "Emily Johnson" displayed anywhere?
4. Does the page show a student list or student details view?

Respond in JSON format:
{
    "is_sis_interface": true/false,
    "success_message_visible": true/false,
    "student_name_visible": true/false,
    "student_details_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_via_vlm(traj: Dict[str, Any]) -> Dict[str, Any]:
    """
    Fallback verification using VLM on screenshot.

    Args:
        traj: Trajectory data with screenshots

    Returns:
        Dict with verification results
    """
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"success": False, "error": "No screenshot available"}

    vlm_result = query_vlm(
        prompt=VLM_VERIFICATION_PROMPT,
        image=final_screenshot,
    )

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})

    # Calculate score based on VLM response
    criteria_met = 0
    total_criteria = 4

    if parsed.get("is_sis_interface"):
        criteria_met += 1
    if parsed.get("success_message_visible"):
        criteria_met += 1
    if parsed.get("student_name_visible"):
        criteria_met += 1
    if parsed.get("student_details_shown"):
        criteria_met += 1

    confidence = parsed.get("confidence", "low")
    confidence_multiplier = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(confidence, 0.8)

    score = int((criteria_met / total_criteria) * 100 * confidence_multiplier)

    return {
        "success": True,
        "passed": criteria_met >= 2,  # At least 2 criteria met
        "score": score,
        "details": parsed,
        "reasoning": parsed.get("reasoning", ""),
    }


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_add_student(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a student named Emily Johnson was added to OpenSIS.

    Primary: Database query verification
    Fallback: VLM-based screenshot analysis

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with exec_in_env function
        task_info: Task info with task_id

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    feedback_parts = []
    result_details = {}

    # Get exec_in_env function
    exec_in_env = env_info.get('exec_in_env')

    # =========================================================================
    # PRIMARY: Database Verification
    # =========================================================================
    if exec_in_env:
        logger.info("Attempting database verification...")
        db_result = verify_student_in_database(exec_in_env)
        result_details['database_check'] = db_result

        if db_result.get("found"):
            record = db_result["record"]
            field_checks = verify_student_fields(record)
            result_details['field_checks'] = field_checks

            # Count matching fields
            matching_fields = sum(1 for v in field_checks.values() if v)
            total_fields = len(field_checks)

            if matching_fields == total_fields:
                # Perfect match
                feedback_parts.append("Database: Student record found with all correct fields")
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": " | ".join(feedback_parts),
                    "details": result_details,
                }
            elif matching_fields >= 2:
                # Partial match (name found, some fields may differ)
                score = int((matching_fields / total_fields) * 100)
                feedback_parts.append(f"Database: Student found, {matching_fields}/{total_fields} fields match")
                return {
                    "passed": True,
                    "score": score,
                    "feedback": " | ".join(feedback_parts),
                    "details": result_details,
                }
            else:
                feedback_parts.append("Database: Student found but fields don't match expected values")
        else:
            feedback_parts.append("Database: Student not found in database")
            if db_result.get("error"):
                feedback_parts.append(f"Query error: {db_result['error']}")
    else:
        feedback_parts.append("Database: No exec_in_env available for database verification")

    # =========================================================================
    # FALLBACK: VLM Verification
    # =========================================================================
    logger.info("Database verification inconclusive, trying VLM fallback...")
    vlm_result = verify_via_vlm(traj)
    result_details['vlm_check'] = vlm_result

    if vlm_result.get("success") and vlm_result.get("passed"):
        score = vlm_result.get("score", 70)
        feedback_parts.append(f"VLM: Success indicators detected (score: {score})")
        feedback_parts.append(f"VLM reasoning: {vlm_result.get('reasoning', 'N/A')}")
        return {
            "passed": True,
            "score": min(score, 85),  # Cap VLM-only score at 85
            "feedback": " | ".join(feedback_parts),
            "details": result_details,
        }

    # =========================================================================
    # FAILURE
    # =========================================================================
    feedback_parts.append("VLM: No success indicators detected")
    if vlm_result.get("reasoning"):
        feedback_parts.append(f"VLM reasoning: {vlm_result['reasoning']}")

    return {
        "passed": False,
        "score": 0,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
