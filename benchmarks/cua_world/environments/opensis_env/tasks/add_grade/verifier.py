"""
Verifier for add_grade task.

Task: Add a grade for 'Sample Student' in 'Mathematics 101':
    - Assignment: Midterm Exam
    - Grade: 85 out of 100

Verification Strategy:
1. PRIMARY: Query MySQL database to verify grade record exists
2. FALLBACK: Use VLM to check for success message in UI
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_GRADE = {
    "student_first_name": "Sample",
    "student_last_name": "Student",
    "course_name": "Mathematics 101",
    "assignment_name": "Midterm Exam",
    "grade_value": 85.0,
}


def verify_grade_in_database(exec_in_env: callable) -> Dict[str, Any]:
    """Query MySQL to verify grade record exists."""
    try:
        query = """SELECT g.grade_id, s.first_name, s.last_name, c.course_name,
                          g.assignment_name, g.grade_value
                   FROM grades g
                   JOIN students s ON g.student_id = s.student_id
                   JOIN courses c ON g.course_id = c.course_id
                   WHERE s.first_name = 'Sample' AND s.last_name = 'Student'
                   AND c.course_name LIKE '%Mathematics%'
                   ORDER BY g.grade_id DESC LIMIT 1"""

        cmd = f"mysql -u opensis_user -p'opensis_password_123' opensis -e \"{query}\" 2>/dev/null"
        result = exec_in_env(cmd)

        if not result or not result.strip():
            return {"found": False, "record": None, "error": None}

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


def verify_grade_fields(record: Dict[str, str]) -> Dict[str, bool]:
    """Verify grade record fields."""
    results = {}

    # Student name
    results["student_name"] = (
        record.get("first_name", "").lower() == EXPECTED_GRADE["student_first_name"].lower() and
        record.get("last_name", "").lower() == EXPECTED_GRADE["student_last_name"].lower()
    )

    # Course
    results["course"] = "mathematics" in record.get("course_name", "").lower()

    # Assignment (partial match)
    results["assignment"] = "midterm" in record.get("assignment_name", "").lower() or \
                           "exam" in record.get("assignment_name", "").lower()

    # Grade value (allow some tolerance)
    try:
        grade_val = float(record.get("grade_value", 0))
        results["grade_value"] = 80 <= grade_val <= 90  # Allow 85 +/- 5
    except ValueError:
        results["grade_value"] = False

    return results


VLM_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully added a grade in OpenSIS.

TASK: Add a grade of 85 for 'Sample Student' in Mathematics, assignment "Midterm Exam".

Look at this screenshot and determine:
1. Is this OpenSIS or a Student Information System interface?
2. Is there a success message about a grade being recorded?
3. Can you see a grades view or gradebook?
4. Is there any indication of "85", "Midterm", or grade entry confirmation?

Respond in JSON format:
{
    "is_sis_interface": true/false,
    "success_message_visible": true/false,
    "grades_view_shown": true/false,
    "grade_confirmation": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_via_vlm(traj: Dict[str, Any]) -> Dict[str, Any]:
    """Fallback verification using VLM."""
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"success": False, "error": "No screenshot available"}

    vlm_result = query_vlm(prompt=VLM_VERIFICATION_PROMPT, image=final_screenshot)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})
    criteria_met = sum([
        parsed.get("is_sis_interface", False),
        parsed.get("success_message_visible", False),
        parsed.get("grades_view_shown", False),
        parsed.get("grade_confirmation", False),
    ])

    confidence = parsed.get("confidence", "low")
    confidence_multiplier = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(confidence, 0.8)
    score = int((criteria_met / 4) * 100 * confidence_multiplier)

    return {
        "success": True,
        "passed": criteria_met >= 2,
        "score": score,
        "details": parsed,
        "reasoning": parsed.get("reasoning", ""),
    }


def verify_add_grade(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a grade was added for Sample Student in Mathematics.

    Primary: Database query verification
    Fallback: VLM-based screenshot analysis
    """
    feedback_parts = []
    result_details = {}

    exec_in_env = env_info.get('exec_in_env')

    # PRIMARY: Database Verification
    if exec_in_env:
        db_result = verify_grade_in_database(exec_in_env)
        result_details['database_check'] = db_result

        if db_result.get("found"):
            record = db_result["record"]
            field_checks = verify_grade_fields(record)
            result_details['field_checks'] = field_checks

            matching_fields = sum(1 for v in field_checks.values() if v)
            total_fields = len(field_checks)

            if matching_fields >= 2:
                score = int((matching_fields / total_fields) * 100)
                feedback_parts.append(f"Database: Grade record found, {matching_fields}/{total_fields} checks pass")
                return {
                    "passed": True,
                    "score": score,
                    "feedback": " | ".join(feedback_parts),
                    "details": result_details,
                }
            else:
                feedback_parts.append("Database: Grade found but values may not match")
        else:
            feedback_parts.append("Database: No grade record found")

    # FALLBACK: VLM Verification
    vlm_result = verify_via_vlm(traj)
    result_details['vlm_check'] = vlm_result

    if vlm_result.get("success") and vlm_result.get("passed"):
        score = vlm_result.get("score", 70)
        feedback_parts.append(f"VLM: Success indicators detected (score: {score})")
        return {
            "passed": True,
            "score": min(score, 85),
            "feedback": " | ".join(feedback_parts),
            "details": result_details,
        }

    feedback_parts.append("Verification failed: No grade record found")
    return {
        "passed": False,
        "score": 0,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
