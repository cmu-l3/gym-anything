"""
Verifier for transfer_student_intake task.

Task: Complete a full transfer student intake in OpenSIS:
  1. Add student Zara Hoffman (Female, DOB: 2007-08-22, Grade 11)
  2. Create three courses: CHEM301, ENG401, HIST201
  3. Enter transfer grades for Zara across those three courses
     (assignment: 'Transfer Final Grade'; scores: 91, 88, 79)

Scoring (total 100, pass >= 60):
  - Criterion A (20 pts): Zara Hoffman student record exists with correct fields
  - Criterion B (25 pts): All three courses exist with correct attributes
  - Criterion C (35 pts): All three grades linked to Zara exist
  - Criterion D (20 pts): Grade values are correct (91, 88, 79) per course

Wrong-target gate: if grades exist for other students under the same
assignment name but NOT for Zara, score = 0.
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any, List

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_STUDENT = {
    "first_name": "Zara",
    "last_name": "Hoffman",
    "date_of_birth": "2007-08-22",
    "gender": "F",
    "grade_level": "11",
}

EXPECTED_COURSES = [
    {"course_code": "CHEM301", "course_name": "Advanced Chemistry", "subject_area": "Science", "grade_level": "11", "credits": "1.0"},
    {"course_code": "ENG401", "course_name": "AP English Language", "subject_area": "English", "grade_level": "11", "credits": "1.0"},
    {"course_code": "HIST201", "course_name": "US History", "subject_area": "Social Studies", "grade_level": "11", "credits": "0.5"},
]

EXPECTED_GRADES = {
    "CHEM301": 91,
    "ENG401": 88,
    "HIST201": 79,
}

ASSIGNMENT_NAME = "Transfer Final Grade"


def _run_query(exec_in_env, query: str) -> List[Dict[str, str]]:
    """Run a MySQL query and return list of row dicts."""
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


def check_student(exec_in_env) -> Dict[str, Any]:
    """Criterion A: Verify Zara Hoffman student record."""
    rows = _run_query(exec_in_env,
        "SELECT student_id, first_name, last_name, date_of_birth, gender, grade_level "
        "FROM students WHERE first_name='Zara' AND last_name='Hoffman'")

    if not rows:
        return {"found": False, "student_id": None, "fields_ok": False, "score": 0,
                "feedback": "Student Zara Hoffman not found in database"}

    rec = rows[0]
    student_id = rec.get("student_id")
    checks = {
        "first_name": rec.get("first_name", "").lower() == "zara",
        "last_name": rec.get("last_name", "").lower() == "hoffman",
        "date_of_birth": EXPECTED_STUDENT["date_of_birth"] in rec.get("date_of_birth", ""),
        "gender": rec.get("gender", "").upper() in ("F", "FEMALE", "2"),
        "grade_level": "11" in rec.get("grade_level", ""),
    }
    all_ok = all(checks.values())
    score = 20 if all_ok else 10 if checks["first_name"] and checks["last_name"] else 0
    return {
        "found": True,
        "student_id": student_id,
        "fields_ok": all_ok,
        "checks": checks,
        "score": score,
        "feedback": f"Student found, fields: {checks}",
    }


def check_courses(exec_in_env) -> Dict[str, Any]:
    """Criterion B: Verify all three courses exist."""
    rows = _run_query(exec_in_env,
        "SELECT course_id, course_name, course_code, subject_area, grade_level, credits "
        "FROM courses WHERE course_code IN ('CHEM301','ENG401','HIST201')")

    found_codes = {r["course_code"]: r for r in rows}
    results = {}
    for exp in EXPECTED_COURSES:
        code = exp["course_code"]
        if code not in found_codes:
            results[code] = {"found": False}
            continue
        rec = found_codes[code]
        fields_ok = (
            exp["course_name"].lower() in rec.get("course_name", "").lower()
            and exp["subject_area"].lower() in rec.get("subject_area", "").lower()
            and exp["grade_level"] in rec.get("grade_level", "")
            and exp["credits"] in rec.get("credits", "")
        )
        results[code] = {"found": True, "fields_ok": fields_ok, "record": rec}

    n_found = sum(1 for v in results.values() if v["found"])
    n_correct = sum(1 for v in results.values() if v.get("fields_ok"))
    # Score: 25 if all 3 correct, else proportional
    if n_correct == 3:
        score = 25
    elif n_found == 3:
        score = 15
    elif n_found == 2:
        score = 10
    elif n_found == 1:
        score = 5
    else:
        score = 0

    return {
        "found_count": n_found,
        "correct_count": n_correct,
        "results": results,
        "score": score,
        "feedback": f"Courses: {n_found}/3 found, {n_correct}/3 fully correct",
    }


def check_grades(exec_in_env, student_id: str) -> Dict[str, Any]:
    """Criteria C+D: Verify grades linked to Zara across the three courses."""
    if not student_id:
        return {"grade_count": 0, "score_c": 0, "score_d": 0,
                "feedback": "Cannot check grades: no student_id"}

    rows = _run_query(exec_in_env,
        f"SELECT g.grade_id, g.student_id, c.course_code, g.assignment_name, g.grade_value "
        f"FROM grades g "
        f"INNER JOIN courses c ON g.course_id = c.course_id "
        f"WHERE g.student_id = {student_id} "
        f"AND c.course_code IN ('CHEM301','ENG401','HIST201')")

    by_course = {r["course_code"]: r for r in rows}
    n_grades = len(by_course)

    # Criterion C: grades exist (35 pts proportional)
    score_c = int((n_grades / 3) * 35)

    # Criterion D: grade values correct (20 pts)
    correct_values = 0
    value_details = {}
    for code, expected_val in EXPECTED_GRADES.items():
        if code in by_course:
            try:
                actual = float(by_course[code].get("grade_value", ""))
                close = abs(actual - expected_val) <= 1.0
                value_details[code] = {"expected": expected_val, "actual": actual, "ok": close}
                if close:
                    correct_values += 1
            except (ValueError, TypeError):
                value_details[code] = {"expected": expected_val, "actual": None, "ok": False}
        else:
            value_details[code] = {"expected": expected_val, "actual": None, "ok": False}

    score_d = int((correct_values / 3) * 20)

    return {
        "grade_count": n_grades,
        "score_c": score_c,
        "score_d": score_d,
        "value_details": value_details,
        "feedback": f"Grades: {n_grades}/3 found, {correct_values}/3 values correct",
    }


def wrong_target_gate(exec_in_env) -> bool:
    """Return True if wrong-target condition detected (grades for other students, not Zara)."""
    rows = _run_query(exec_in_env,
        "SELECT COUNT(*) as cnt FROM grades g "
        "INNER JOIN students s ON g.student_id = s.student_id "
        "INNER JOIN courses c ON g.course_id = c.course_id "
        "WHERE (s.first_name != 'Zara' OR s.last_name != 'Hoffman') "
        "AND c.course_code IN ('CHEM301','ENG401','HIST201') "
        "AND g.assignment_name = 'Transfer Final Grade'")
    if rows:
        try:
            return int(rows[0].get("cnt", 0)) > 0
        except (ValueError, TypeError):
            pass
    return False


VLM_PROMPT = """You are verifying if an agent successfully completed a transfer student intake in OpenSIS.

Tasks completed should include:
1. A student named 'Zara Hoffman' was added to the system
2. Three courses (CHEM301, ENG401, HIST201) were created
3. Transfer grades were entered for Zara Hoffman

Look at the screenshot and respond in JSON:
{
    "is_sis_interface": true/false,
    "student_visible": true/false,
    "courses_visible": true/false,
    "grades_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_transfer_student_intake(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify complete transfer student intake for Zara Hoffman.
    Returns dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str).
    """
    feedback_parts = []
    result_details = {}
    exec_in_env = env_info.get('exec_in_env')

    if exec_in_env:
        # Wrong-target gate
        if wrong_target_gate(exec_in_env):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Wrong-target gate triggered: grades entered for wrong student",
                "details": {"wrong_target": True},
            }

        # Criterion A: student
        student_result = check_student(exec_in_env)
        result_details["student"] = student_result
        feedback_parts.append(student_result["feedback"])
        score_a = student_result["score"]
        student_id = student_result.get("student_id")

        # Criterion B: courses
        course_result = check_courses(exec_in_env)
        result_details["courses"] = course_result
        feedback_parts.append(course_result["feedback"])
        score_b = course_result["score"]

        # Criteria C+D: grades
        grade_result = check_grades(exec_in_env, student_id)
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
    criteria = [parsed.get("student_visible"), parsed.get("courses_visible"), parsed.get("grades_visible")]
    met = sum(1 for c in criteria if c)
    confidence_mult = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(parsed.get("confidence", "low"), 0.8)
    score = int((met / 3) * 85 * confidence_mult)

    return {
        "passed": met >= 2,
        "score": score,
        "feedback": f"VLM fallback: {met}/3 criteria met | {parsed.get('reasoning', '')}",
        "details": {"vlm": parsed},
    }
