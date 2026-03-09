"""
Verifier for teacher_onboarding_complete task.

Task:
  1. Create staff Jennifer Torres (Teacher, email: jtorres@riverside.edu)
  2. Create course Spanish III (SPAN301, Foreign Language, Gr10, 1.0cr)
  3. Enter 'Placement Test' grades for Carlos Mendez (82) and Ana Nguyen (89) in SPAN301

Scoring (total 100, pass >= 60):
  - Criterion A (25 pts): Jennifer Torres staff record exists with correct fields
  - Criterion B (25 pts): SPAN301 course exists with correct attributes
  - Criterion C (25 pts): Both Placement Test grade records exist in SPAN301
  - Criterion D (25 pts): Grade values are correct (Carlos=82, Ana=89)

Wrong-target gate: 'Placement Test' grades in SPAN301 for students other than
Carlos/Ana returns score=0.
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any, List

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_STAFF = {
    "first_name": "Jennifer",
    "last_name": "Torres",
    "email": "jtorres@riverside.edu",
    "profile": "Teacher",
}

EXPECTED_COURSE = {
    "course_code": "SPAN301",
    "course_name": "Spanish III",
    "subject_area": "Foreign Language",
    "grade_level": "10",
    "credits": "1.0",
}

EXPECTED_GRADES = [
    {"first_name": "Carlos", "last_name": "Mendez", "value": 82},
    {"first_name": "Ana",    "last_name": "Nguyen",  "value": 89},
]


def _run_query(exec_in_env, query: str) -> List[Dict[str, str]]:
    cmd = f"mysql -u opensis_user -p'opensis_password_123' opensis -e \"{query}\" 2>/dev/null"
    result = exec_in_env(cmd)
    if not result or not result.strip():
        return []
    lines = result.strip().split('\n')
    if len(lines) < 2:
        return []
    headers = lines[0].split('\t')
    rows = []
    for line in lines[1:]:
        values = line.split('\t')
        if len(values) == len(headers):
            rows.append(dict(zip(headers, values)))
    return rows


def check_staff(exec_in_env) -> Dict[str, Any]:
    """Criterion A: Verify Jennifer Torres staff record."""
    rows = _run_query(exec_in_env,
        "SELECT staff_id, first_name, last_name, email, profile "
        "FROM staff WHERE first_name='Jennifer' AND last_name='Torres'")

    if not rows:
        return {"found": False, "score": 0,
                "feedback": "Staff Jennifer Torres not found"}

    rec = rows[0]
    checks = {
        "first_name": rec.get("first_name", "").lower() == "jennifer",
        "last_name": rec.get("last_name", "").lower() == "torres",
        "email": "jtorres@riverside.edu" in rec.get("email", "").lower(),
        "profile": "teacher" in rec.get("profile", "").lower(),
    }
    correct = sum(1 for v in checks.values() if v)
    score = 25 if correct >= 3 else 15 if correct >= 2 else 0
    return {
        "found": True,
        "checks": checks,
        "score": score,
        "feedback": f"Staff Jennifer Torres: {correct}/4 fields correct",
    }


def check_course(exec_in_env) -> Dict[str, Any]:
    """Criterion B: Verify SPAN301 course."""
    rows = _run_query(exec_in_env,
        "SELECT course_id, course_name, course_code, subject_area, grade_level, credits "
        "FROM courses WHERE course_code='SPAN301'")

    if not rows:
        return {"found": False, "course_id": None, "score": 0,
                "feedback": "Course SPAN301 not found"}

    rec = rows[0]
    course_id = rec.get("course_id")
    checks = {
        "course_name": "spanish" in rec.get("course_name", "").lower(),
        "subject_area": "foreign" in rec.get("subject_area", "").lower() or "language" in rec.get("subject_area", "").lower(),
        "grade_level": "10" in rec.get("grade_level", ""),
        "credits": "1" in rec.get("credits", ""),
    }
    correct = sum(1 for v in checks.values() if v)
    score = 25 if correct >= 3 else 15 if correct >= 2 else 5
    return {
        "found": True,
        "course_id": course_id,
        "checks": checks,
        "score": score,
        "feedback": f"Course SPAN301: {correct}/4 fields correct",
    }


def check_grades(exec_in_env, course_id: str) -> Dict[str, Any]:
    """Criteria C+D: Verify Placement Test grades for Carlos and Ana in SPAN301."""
    if not course_id:
        return {"grade_count": 0, "score_c": 0, "score_d": 0,
                "feedback": "Cannot check grades: SPAN301 not found"}

    rows = _run_query(exec_in_env,
        f"SELECT g.grade_id, s.first_name, s.last_name, g.grade_value "
        f"FROM grades g "
        f"INNER JOIN students s ON g.student_id = s.student_id "
        f"WHERE g.course_id = {course_id} "
        f"AND g.assignment_name = 'Placement Test' "
        f"AND s.first_name IN ('Carlos','Ana')")

    by_first = {r["first_name"]: r for r in rows}
    n_found = len(by_first)
    score_c = int((n_found / 2) * 25)

    correct_values = 0
    value_details = {}
    for exp in EXPECTED_GRADES:
        fname = exp["first_name"]
        if fname in by_first:
            try:
                actual = float(by_first[fname].get("grade_value", ""))
                ok = abs(actual - exp["value"]) <= 1.0
                value_details[fname] = {"expected": exp["value"], "actual": actual, "ok": ok}
                if ok:
                    correct_values += 1
            except (ValueError, TypeError):
                value_details[fname] = {"expected": exp["value"], "actual": None, "ok": False}
        else:
            value_details[fname] = {"expected": exp["value"], "actual": None, "ok": False}

    score_d = int((correct_values / 2) * 25)

    return {
        "grade_count": n_found,
        "score_c": score_c,
        "score_d": score_d,
        "value_details": value_details,
        "feedback": f"Placement Test grades: {n_found}/2 found, {correct_values}/2 values correct",
    }


def wrong_target_gate(exec_in_env, course_id: str) -> bool:
    """Return True if Placement Test grades exist for unexpected students in SPAN301."""
    if not course_id:
        return False
    rows = _run_query(exec_in_env,
        f"SELECT COUNT(*) as cnt FROM grades g "
        f"INNER JOIN students s ON g.student_id = s.student_id "
        f"WHERE g.course_id = {course_id} "
        f"AND g.assignment_name = 'Placement Test' "
        f"AND s.first_name NOT IN ('Carlos','Ana')")
    if rows:
        try:
            return int(rows[0].get("cnt", 0)) > 0
        except (ValueError, TypeError):
            pass
    return False


VLM_PROMPT = """You are verifying if an agent successfully completed teacher onboarding in OpenSIS.

The agent should have:
1. Added staff Jennifer Torres as a Teacher
2. Created course Spanish III (SPAN301)
3. Entered Placement Test scores for Carlos Mendez and Ana Nguyen

Look at the screenshot and respond in JSON:
{
    "is_sis_interface": true/false,
    "staff_visible": true/false,
    "course_visible": true/false,
    "grades_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_teacher_onboarding_complete(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify teacher onboarding: Jennifer Torres, SPAN301, and placement test grades.
    Returns dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str).
    """
    feedback_parts = []
    result_details = {}
    exec_in_env = env_info.get('exec_in_env')

    if exec_in_env:
        # Get course first (needed for gate)
        course_result = check_course(exec_in_env)
        result_details["course"] = course_result
        course_id = course_result.get("course_id")

        # Wrong-target gate
        if wrong_target_gate(exec_in_env, course_id):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong-target gate triggered: Placement Test grades entered for unexpected students in SPAN301",
                "details": {"wrong_target": True},
            }

        # Criterion A: staff
        staff_result = check_staff(exec_in_env)
        result_details["staff"] = staff_result
        feedback_parts.append(staff_result["feedback"])
        score_a = staff_result["score"]

        # Criterion B: course (already checked)
        feedback_parts.append(course_result["feedback"])
        score_b = course_result["score"]

        # Criteria C+D: grades
        grade_result = check_grades(exec_in_env, course_id)
        result_details["grades"] = grade_result
        feedback_parts.append(grade_result["feedback"])
        score_c = grade_result["score_c"]
        score_d = grade_result["score_d"]

        total_score = score_a + score_b + score_c + score_d
        passed = total_score >= 60

        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details,
        }

    # VLM fallback
    logger.info("No exec_in_env, falling back to VLM...")
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No exec_in_env and no screenshot available", "details": {}}

    vlm_result = query_vlm(prompt=VLM_PROMPT, image=final_screenshot)
    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM query failed", "details": {}}

    parsed = vlm_result.get("parsed", {})
    criteria = [parsed.get("staff_visible"), parsed.get("course_visible"), parsed.get("grades_visible")]
    met = sum(1 for c in criteria if c)
    confidence_mult = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(parsed.get("confidence", "low"), 0.8)
    score = int((met / 3) * 85 * confidence_mult)

    return {
        "passed": met >= 2,
        "score": score,
        "feedback": f"VLM fallback: {met}/3 criteria met | {parsed.get('reasoning', '')}",
        "details": {"vlm": parsed},
    }
