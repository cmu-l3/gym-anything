"""
Verifier for search_student task.

Task: Search for 'Sample Student' in OpenSIS and display their information.

This is primarily a UI-based task, so VLM verification is the primary method.
We verify that:
1. The user navigated to the students section
2. A search was performed
3. 'Sample Student' information is displayed

Verification Strategy:
1. PRIMARY: VLM analysis of screenshot (UI-based task)
2. SECONDARY: Check if correct page/URL indicates student was found
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_STUDENT = {
    "first_name": "Sample",
    "last_name": "Student",
}


VLM_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully searched for and found a student in OpenSIS (Student Information System).

TASK: Search for "Sample Student" and display their information.

Look at this screenshot and determine:
1. Is this OpenSIS or a Student Information System interface?
2. Is there a student list or search results displayed?
3. Can you see "Sample" or "Student" in the displayed content?
4. Does it look like a student profile or student details page?
5. Is there a search box visible with search text or results?

Respond in JSON format:
{
    "is_sis_interface": true/false,
    "student_list_visible": true/false,
    "target_student_visible": true/false,
    "student_details_shown": true/false,
    "search_performed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_via_vlm(traj: Dict[str, Any]) -> Dict[str, Any]:
    """Primary verification using VLM on screenshot."""
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"success": False, "error": "No screenshot available"}

    vlm_result = query_vlm(prompt=VLM_VERIFICATION_PROMPT, image=final_screenshot)

    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})

    # Calculate criteria met
    criteria_met = 0
    total_criteria = 5

    if parsed.get("is_sis_interface"):
        criteria_met += 1
    if parsed.get("student_list_visible"):
        criteria_met += 1
    if parsed.get("target_student_visible"):
        criteria_met += 2  # Worth double since this is the main objective
    if parsed.get("student_details_shown"):
        criteria_met += 1
    if parsed.get("search_performed"):
        criteria_met += 1

    confidence = parsed.get("confidence", "low")
    confidence_multiplier = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(confidence, 0.8)

    # Normalize score (max criteria is 6 due to double weight)
    score = int((criteria_met / 6) * 100 * confidence_multiplier)

    # Passed if we can see the target student
    passed = parsed.get("target_student_visible", False) or (criteria_met >= 3)

    return {
        "success": True,
        "passed": passed,
        "score": score,
        "details": parsed,
        "reasoning": parsed.get("reasoning", ""),
    }


def verify_student_exists_in_db(exec_in_env: callable) -> bool:
    """Quick check that the student exists in database."""
    try:
        query = "SELECT COUNT(*) FROM students WHERE first_name='Sample' AND last_name='Student'"
        cmd = f"mysql -u opensis_user -p'opensis_password_123' opensis -N -e \"{query}\" 2>/dev/null"
        result = exec_in_env(cmd)
        if result and result.strip():
            count = int(result.strip())
            return count > 0
    except Exception as e:
        logger.error(f"Database check failed: {e}")
    return False


def verify_search_student(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the user searched for and found 'Sample Student'.

    Primary: VLM-based screenshot analysis (this is a UI task)
    Secondary: Verify student exists in database
    """
    feedback_parts = []
    result_details = {}

    exec_in_env = env_info.get('exec_in_env')

    # Check student exists (sanity check)
    if exec_in_env:
        student_exists = verify_student_exists_in_db(exec_in_env)
        result_details['student_in_db'] = student_exists
        if not student_exists:
            feedback_parts.append("Note: Student may not exist in database")

    # PRIMARY: VLM Verification
    logger.info("Performing VLM verification...")
    vlm_result = verify_via_vlm(traj)
    result_details['vlm_check'] = vlm_result

    if vlm_result.get("success"):
        if vlm_result.get("passed"):
            score = vlm_result.get("score", 70)
            feedback_parts.append(f"VLM: Search successful, student found (score: {score})")
            feedback_parts.append(f"Reasoning: {vlm_result.get('reasoning', 'N/A')}")
            return {
                "passed": True,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "details": result_details,
            }
        else:
            feedback_parts.append("VLM: Student not clearly visible in search results")
            feedback_parts.append(f"Reasoning: {vlm_result.get('reasoning', 'N/A')}")
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error', 'Unknown error')}")

    return {
        "passed": False,
        "score": vlm_result.get("score", 0) if vlm_result.get("success") else 0,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
