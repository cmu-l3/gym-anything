"""
Verifier for student_grade_portfolio task.

Task:
  1. Create 4 courses: STAT101, WRIT101, CIVIC101, PHOTO101
  2. Enter 'Semester Final Grade' for Brandon Lee in each:
     STAT101=85, WRIT101=92, CIVIC101=78, PHOTO101=96

Scoring (total 100, pass >= 60):
  - Criterion A (10 pts): Brandon Lee student record exists (pre-seeded sanity)
  - Criterion B (25 pts): All four courses exist with correct attributes
  - Criterion C (40 pts): All four grade records linked to Brandon exist
  - Criterion D (25 pts): Grade values are correct (85, 92, 78, 96)

Wrong-target gate: 'Semester Final Grade' entries linked to other students
in the four target courses returns score=0.
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any, List

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_COURSES = [
    {"course_code": "STAT101",  "course_name": "AP Statistics",    "subject_area": "Math",          "grade_level": "11", "credits": "1.0"},
    {"course_code": "WRIT101",  "course_name": "Creative Writing",  "subject_area": "English",       "grade_level": "11", "credits": "1.0"},
    {"course_code": "CIVIC101", "course_name": "Civics",            "subject_area": "Social Studies","grade_level": "11", "credits": "0.5"},
    {"course_code": "PHOTO101", "course_name": "Photography",       "subject_area": "Arts",          "grade_level": "11", "credits": "0.5"},
]

EXPECTED_GRADES = {
    "STAT101":  85,
    "WRIT101":  92,
    "CIVIC101": 78,
    "PHOTO101": 96,
}

ASSIGNMENT_NAME = "Semester Final Grade"


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


def check_brandon(exec_in_env) -> Dict[str, Any]:
    """Criterion A: Verify Brandon Lee pre-seeded record."""
    rows = _run_query(exec_in_env,
        "SELECT student_id FROM students WHERE first_name='Brandon' AND last_name='Lee'")
    if rows:
        return {"found": True, "student_id": rows[0]["student_id"], "score": 10,
                "feedback": "Brandon Lee student record found"}
    return {"found": False, "student_id": None, "score": 0,
            "feedback": "Brandon Lee student record not found"}


def check_courses(exec_in_env) -> Dict[str, Any]:
    """Criterion B: Verify all four courses exist."""
    codes = "','".join(e["course_code"] for e in EXPECTED_COURSES)
    rows = _run_query(exec_in_env,
        f"SELECT course_id, course_name, course_code, subject_area, grade_level, credits "
        f"FROM courses WHERE course_code IN ('{codes}')")

    found = {r["course_code"]: r for r in rows}
    results = {}
    for exp in EXPECTED_COURSES:
        code = exp["course_code"]
        if code not in found:
            results[code] = {"found": False, "fields_ok": False}
            continue
        rec = found[code]
        fields_ok = (
            exp["course_name"].lower() in rec.get("course_name", "").lower()
            and exp["subject_area"].lower() in rec.get("subject_area", "").lower()
            and exp["grade_level"] in rec.get("grade_level", "")
            and exp["credits"] in rec.get("credits", "")
        )
        results[code] = {"found": True, "fields_ok": fields_ok, "record": rec}

    n_found = sum(1 for v in results.values() if v["found"])
    n_correct = sum(1 for v in results.values() if v.get("fields_ok"))
    score = 25 if n_correct == 4 else int((n_found / 4) * 20)
    return {
        "found_count": n_found,
        "correct_count": n_correct,
        "results": results,
        "score": score,
        "feedback": f"Courses: {n_found}/4 found, {n_correct}/4 fully correct",
    }


def check_grades(exec_in_env, student_id: str) -> Dict[str, Any]:
    """Criteria C+D: Verify Semester Final Grades for Brandon in all 4 courses."""
    if not student_id:
        return {"grade_count": 0, "score_c": 0, "score_d": 0,
                "feedback": "Cannot check grades: Brandon Lee not found"}

    codes = "','".join(EXPECTED_GRADES.keys())
    rows = _run_query(exec_in_env,
        f"SELECT g.grade_id, c.course_code, g.assignment_name, g.grade_value "
        f"FROM grades g "
        f"INNER JOIN courses c ON g.course_id = c.course_id "
        f"WHERE g.student_id = {student_id} "
        f"AND c.course_code IN ('{codes}') "
        f"AND g.assignment_name = 'Semester Final Grade'")

    by_code = {r["course_code"]: r for r in rows}
    n_grades = len(by_code)
    score_c = int((n_grades / 4) * 40)

    correct_values = 0
    value_details = {}
    for code, expected_val in EXPECTED_GRADES.items():
        if code in by_code:
            try:
                actual = float(by_code[code].get("grade_value", ""))
                ok = abs(actual - expected_val) <= 1.0
                value_details[code] = {"expected": expected_val, "actual": actual, "ok": ok}
                if ok:
                    correct_values += 1
            except (ValueError, TypeError):
                value_details[code] = {"expected": expected_val, "actual": None, "ok": False}
        else:
            value_details[code] = {"expected": expected_val, "actual": None, "ok": False}

    score_d = int((correct_values / 4) * 25)

    return {
        "grade_count": n_grades,
        "score_c": score_c,
        "score_d": score_d,
        "value_details": value_details,
        "feedback": f"Grades: {n_grades}/4 found, {correct_values}/4 values correct",
    }


def wrong_target_gate(exec_in_env) -> bool:
    """Trigger if Semester Final Grade entries exist for non-Brandon students in these courses."""
    codes = "','".join(EXPECTED_GRADES.keys())
    rows = _run_query(exec_in_env,
        f"SELECT COUNT(*) as cnt FROM grades g "
        f"INNER JOIN students s ON g.student_id = s.student_id "
        f"INNER JOIN courses c ON g.course_id = c.course_id "
        f"WHERE c.course_code IN ('{codes}') "
        f"AND g.assignment_name = 'Semester Final Grade' "
        f"AND NOT (s.first_name='Brandon' AND s.last_name='Lee')")
    if rows:
        try:
            return int(rows[0].get("cnt", 0)) > 0
        except (ValueError, TypeError):
            pass
    return False


VLM_PROMPT = """You are verifying if an agent successfully built an academic portfolio in OpenSIS.

The agent should have:
1. Created four courses (STAT101, WRIT101, CIVIC101, PHOTO101)
2. Entered Semester Final Grades for student Brandon Lee in each course

Look at the screenshot and respond in JSON:
{
    "is_sis_interface": true/false,
    "courses_visible": true/false,
    "student_grades_visible": true/false,
    "brandon_lee_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_student_grade_portfolio(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Brandon Lee's academic portfolio setup: courses and grades.
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
                "feedback": "Wrong-target gate triggered: Semester Final Grade entries for unexpected students",
                "details": {"wrong_target": True},
            }

        # Criterion A: student record
        brandon_result = check_brandon(exec_in_env)
        result_details["student"] = brandon_result
        feedback_parts.append(brandon_result["feedback"])
        score_a = brandon_result["score"]
        student_id = brandon_result.get("student_id")

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
    criteria = [parsed.get("courses_visible"), parsed.get("student_grades_visible"), parsed.get("brandon_lee_visible")]
    met = sum(1 for c in criteria if c)
    confidence_mult = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(parsed.get("confidence", "low"), 0.8)
    score = int((met / 3) * 85 * confidence_mult)

    return {
        "passed": met >= 2,
        "score": score,
        "feedback": f"VLM fallback: {met}/3 criteria met | {parsed.get('reasoning', '')}",
        "details": {"vlm": parsed},
    }
