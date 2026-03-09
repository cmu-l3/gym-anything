"""
Verifier for create_course task.

Task: Create a new course in OpenSIS with:
    - Course name: Advanced Chemistry
    - Course code: CHEM201
    - Subject area: Science
    - Grade level: 11
    - Credits: 1.0

Verification Strategy:
1. PRIMARY: Query MySQL database to verify course record exists
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

# Expected course data
EXPECTED_COURSE = {
    "course_name": "Advanced Chemistry",
    "course_code": "CHEM201",
    "subject_area": "Science",
    "grade_level": "11",
    "credits": "1.0",
}


def verify_course_in_database(exec_in_env: callable) -> Dict[str, Any]:
    """Query MySQL to verify course record exists."""
    try:
        query = """SELECT course_id, course_name, course_code, subject_area, grade_level, credits
                   FROM courses
                   WHERE course_code = 'CHEM201' OR course_name LIKE '%Advanced Chemistry%'"""

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


def verify_course_fields(record: Dict[str, str]) -> Dict[str, bool]:
    """Verify that course record fields match expected values."""
    results = {}

    # Course name (partial match)
    results["course_name"] = "chemistry" in record.get("course_name", "").lower()

    # Course code (exact match)
    results["course_code"] = record.get("course_code", "").upper() == EXPECTED_COURSE["course_code"]

    # Subject area
    results["subject_area"] = "science" in record.get("subject_area", "").lower()

    # Grade level
    results["grade_level"] = "11" in record.get("grade_level", "")

    return results


VLM_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully created a new course in OpenSIS (Student Information System).

TASK: Create a course named "Advanced Chemistry" with code "CHEM201".

Look at this screenshot and determine:
1. Is this OpenSIS or a Student Information System interface?
2. Is there a success message indicating a course was created?
3. Can you see "Advanced Chemistry" or "CHEM201" displayed anywhere?
4. Does the page show a course list or course details view?

Respond in JSON format:
{
    "is_sis_interface": true/false,
    "success_message_visible": true/false,
    "course_visible": true/false,
    "course_details_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_via_vlm(traj: Dict[str, Any]) -> Dict[str, Any]:
    """Fallback verification using VLM on screenshot."""
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
        parsed.get("course_visible", False),
        parsed.get("course_details_shown", False),
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


def verify_create_course(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a course "Advanced Chemistry" was created in OpenSIS.

    Primary: Database query verification
    Fallback: VLM-based screenshot analysis
    """
    feedback_parts = []
    result_details = {}

    exec_in_env = env_info.get('exec_in_env')

    # PRIMARY: Database Verification
    if exec_in_env:
        db_result = verify_course_in_database(exec_in_env)
        result_details['database_check'] = db_result

        if db_result.get("found"):
            record = db_result["record"]
            field_checks = verify_course_fields(record)
            result_details['field_checks'] = field_checks

            matching_fields = sum(1 for v in field_checks.values() if v)
            total_fields = len(field_checks)

            if matching_fields >= 2:
                score = int((matching_fields / total_fields) * 100)
                feedback_parts.append(f"Database: Course found, {matching_fields}/{total_fields} fields match")
                return {
                    "passed": True,
                    "score": score,
                    "feedback": " | ".join(feedback_parts),
                    "details": result_details,
                }
            else:
                feedback_parts.append("Database: Course found but fields don't match")
        else:
            feedback_parts.append("Database: Course not found")

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

    feedback_parts.append("Verification failed: Course not found in database or UI")
    return {
        "passed": False,
        "score": 0,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
