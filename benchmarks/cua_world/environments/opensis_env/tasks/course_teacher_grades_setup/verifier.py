"""
Verifier for course_teacher_grades_setup task.

Task:
  1. Create staff Dr. Evelyn Park (Teacher, email: epark@school.edu)
  2. Create course Advanced Biology (BIO401, Science, Gr12, 1.0cr)
  3. Enter 'Lab Practical' grades for Sophie Walsh (94), Kevin O'Brien (87), Maya Rodriguez (91)

Scoring (total 100, pass >= 60):
  - Criterion A (25 pts): Dr. Evelyn Park staff record exists with correct fields
  - Criterion B (25 pts): BIO401 course exists with correct attributes
  - Criterion C (25 pts): All three Lab Practical grade records exist linked to BIO401
  - Criterion D (25 pts): Grade values are correct (94, 87, 91)

Wrong-target gate: if 'Lab Practical' grades exist for OTHER students in BIO401, score=0.
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
    "first_name": "Evelyn",
    "last_name": "Park",
    "email": "epark@school.edu",
    "title": "Dr.",
    "profile": "Teacher",
}

EXPECTED_COURSE = {
    "course_code": "BIO401",
    "course_name": "Advanced Biology",
    "subject_area": "Science",
    "grade_level": "12",
    "credits": "1.0",
}

EXPECTED_GRADES = [
    {"first_name": "Sophie", "last_name": "Walsh",     "value": 94},
    {"first_name": "Kevin",  "last_name": "OBrien",    "value": 87},  # handles apostrophe
    {"first_name": "Maya",   "last_name": "Rodriguez", "value": 91},
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
    """Criterion A: Verify Dr. Evelyn Park staff record."""
    rows = _run_query(exec_in_env,
        "SELECT staff_id, title, first_name, last_name, email, profile "
        "FROM staff WHERE first_name='Evelyn' AND last_name='Park'")

    if not rows:
        return {"found": False, "score": 0,
                "feedback": "Staff Dr. Evelyn Park not found"}

    rec = rows[0]
    checks = {
        "first_name": rec.get("first_name", "").lower() == "evelyn",
        "last_name": rec.get("last_name", "").lower() == "park",
        "email": "epark@school.edu" in rec.get("email", "").lower(),
        "title": "dr" in rec.get("title", "").lower(),
        "profile": "teacher" in rec.get("profile", "").lower(),
    }
    correct = sum(1 for v in checks.values() if v)
    score = 25 if correct >= 4 else 15 if correct >= 2 else 0
    return {
        "found": True,
        "checks": checks,
        "score": score,
        "feedback": f"Staff Evelyn Park: {correct}/5 fields correct",
    }


def check_course(exec_in_env) -> Dict[str, Any]:
    """Criterion B: Verify BIO401 course."""
    rows = _run_query(exec_in_env,
        "SELECT course_id, course_name, course_code, subject_area, grade_level, credits "
        "FROM courses WHERE course_code='BIO401'")

    if not rows:
        return {"found": False, "course_id": None, "score": 0,
                "feedback": "Course BIO401 not found"}

    rec = rows[0]
    course_id = rec.get("course_id")
    checks = {
        "course_name": "biology" in rec.get("course_name", "").lower(),
        "subject_area": "science" in rec.get("subject_area", "").lower(),
        "grade_level": "12" in rec.get("grade_level", ""),
        "credits": "1" in rec.get("credits", ""),
    }
    correct = sum(1 for v in checks.values() if v)
    score = 25 if correct >= 3 else 15 if correct >= 2 else 5
    return {
        "found": True,
        "course_id": course_id,
        "checks": checks,
        "score": score,
        "feedback": f"Course BIO401: {correct}/4 fields correct",
    }


def check_grades(exec_in_env, course_id: str) -> Dict[str, Any]:
    """Criteria C+D: Verify Lab Practical grades for the three students in BIO401."""
    if not course_id:
        return {"grade_count": 0, "score_c": 0, "score_d": 0,
                "feedback": "Cannot check grades: BIO401 course not found"}

    # Query grades for any of the three students in BIO401
    rows = _run_query(exec_in_env,
        f"SELECT g.grade_id, s.first_name, s.last_name, g.grade_value, g.assignment_name "
        f"FROM grades g "
        f"INNER JOIN students s ON g.student_id = s.student_id "
        f"WHERE g.course_id = {course_id} "
        f"AND g.assignment_name = 'Lab Practical' "
        f"AND s.first_name IN ('Sophie','Kevin','Maya')")

    # Index by first name (handles O'Brien vs OBrien)
    by_first = {r["first_name"]: r for r in rows}
    n_found = len(by_first)

    # Criterion C (25 pts): grades found
    score_c = int((n_found / 3) * 25)

    # Criterion D (25 pts): values correct
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

    score_d = int((correct_values / 3) * 25)

    return {
        "grade_count": n_found,
        "score_c": score_c,
        "score_d": score_d,
        "value_details": value_details,
        "feedback": f"Lab Practical grades: {n_found}/3 found, {correct_values}/3 values correct",
    }


def wrong_target_gate(exec_in_env, course_id: str) -> bool:
    """Return True if Lab Practical grades exist for unexpected students in BIO401."""
    if not course_id:
        return False
    rows = _run_query(exec_in_env,
        f"SELECT COUNT(*) as cnt FROM grades g "
        f"INNER JOIN students s ON g.student_id = s.student_id "
        f"WHERE g.course_id = {course_id} "
        f"AND g.assignment_name = 'Lab Practical' "
        f"AND s.first_name NOT IN ('Sophie','Kevin','Maya')")
    if rows:
        try:
            return int(rows[0].get("cnt", 0)) > 0
        except (ValueError, TypeError):
            pass
    return False


VLM_PROMPT = """You are verifying if an agent successfully set up a science department in OpenSIS.

The agent should have:
1. Added staff Dr. Evelyn Park as Teacher
2. Created course Advanced Biology (BIO401)
3. Entered Lab Practical grades for three Grade 12 students

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


def verify_course_teacher_grades_setup(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify science department setup: staff, course, and grades.
    Returns dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str).
    """
    feedback_parts = []
    result_details = {}
    exec_in_env = env_info.get('exec_in_env')

    if exec_in_env:
        # Check course first (needed for gate and grade checks)
        course_result = check_course(exec_in_env)
        result_details["course"] = course_result
        course_id = course_result.get("course_id")

        # Wrong-target gate
        if wrong_target_gate(exec_in_env, course_id):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong-target gate triggered: Lab Practical grades entered for unexpected students in BIO401",
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
