"""
Verifier for record_attendance task.

Task: Record attendance for 'Sample Student' for today's date as 'Present'.

Verification Strategy:
1. PRIMARY: Query MySQL database to verify attendance record exists
2. FALLBACK: Use VLM to check for success message in UI
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any
from datetime import date

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_STUDENT = {
    "first_name": "Sample",
    "last_name": "Student",
}
EXPECTED_STATUS = "present"


def verify_attendance_in_database(exec_in_env: callable) -> Dict[str, Any]:
    """Query MySQL to verify attendance record exists."""
    try:
        # Get today's date
        today = date.today().strftime("%Y-%m-%d")

        query = f"""SELECT a.attendance_id, s.first_name, s.last_name, a.attendance_date, a.status
                    FROM attendance a
                    JOIN students s ON a.student_id = s.student_id
                    WHERE s.first_name = 'Sample' AND s.last_name = 'Student'
                    AND a.attendance_date = '{today}'"""

        cmd = f"mysql -u opensis_user -p'opensis_password_123' opensis -e \"{query}\" 2>/dev/null"
        result = exec_in_env(cmd)

        if not result or not result.strip():
            # Try checking for any recent attendance for this student
            query_any = """SELECT a.attendance_id, s.first_name, s.last_name, a.attendance_date, a.status
                          FROM attendance a
                          JOIN students s ON a.student_id = s.student_id
                          WHERE s.first_name = 'Sample' AND s.last_name = 'Student'
                          ORDER BY a.attendance_id DESC LIMIT 1"""
            cmd_any = f"mysql -u opensis_user -p'opensis_password_123' opensis -e \"{query_any}\" 2>/dev/null"
            result = exec_in_env(cmd_any)

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


def verify_attendance_fields(record: Dict[str, str]) -> Dict[str, bool]:
    """Verify attendance record fields."""
    results = {}

    # Student name
    results["student_name"] = (
        record.get("first_name", "").lower() == EXPECTED_STUDENT["first_name"].lower() and
        record.get("last_name", "").lower() == EXPECTED_STUDENT["last_name"].lower()
    )

    # Status is present
    results["status_present"] = record.get("status", "").lower() in ("present", "p", "1")

    # Has a date
    results["has_date"] = bool(record.get("attendance_date"))

    return results


VLM_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully recorded attendance in OpenSIS.

TASK: Mark 'Sample Student' as Present for today.

Look at this screenshot and determine:
1. Is this OpenSIS or a Student Information System interface?
2. Is there a success message about attendance being recorded?
3. Can you see an attendance view or list?
4. Is there any indication that "Sample Student" or "Present" was recorded?

Respond in JSON format:
{
    "is_sis_interface": true/false,
    "success_message_visible": true/false,
    "attendance_view_shown": true/false,
    "record_confirmation": true/false,
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
        parsed.get("attendance_view_shown", False),
        parsed.get("record_confirmation", False),
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


def verify_record_attendance(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that attendance was recorded for Sample Student.

    Primary: Database query verification
    Fallback: VLM-based screenshot analysis
    """
    feedback_parts = []
    result_details = {}

    exec_in_env = env_info.get('exec_in_env')

    # PRIMARY: Database Verification
    if exec_in_env:
        db_result = verify_attendance_in_database(exec_in_env)
        result_details['database_check'] = db_result

        if db_result.get("found"):
            record = db_result["record"]
            field_checks = verify_attendance_fields(record)
            result_details['field_checks'] = field_checks

            matching_fields = sum(1 for v in field_checks.values() if v)
            total_fields = len(field_checks)

            if matching_fields >= 2:
                score = int((matching_fields / total_fields) * 100)
                feedback_parts.append(f"Database: Attendance record found, {matching_fields}/{total_fields} checks pass")
                return {
                    "passed": True,
                    "score": score,
                    "feedback": " | ".join(feedback_parts),
                    "details": result_details,
                }
            else:
                feedback_parts.append("Database: Attendance found but status/date may not match")
        else:
            feedback_parts.append("Database: No attendance record found")

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

    feedback_parts.append("Verification failed: No attendance record found")
    return {
        "passed": False,
        "score": 0,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
