"""
Verifier for multi_student_attendance_audit task.

Task: Record attendance for three 10th-grade students on 2024-11-04:
  - Miguel Santos: Present
  - Aisha Patel: Absent
  - Dmitri Volkov: Tardy

Scoring (total 100, pass >= 60):
  - Criterion A (33 pts): Miguel Santos has Present on 2024-11-04
  - Criterion B (33 pts): Aisha Patel has Absent on 2024-11-04
  - Criterion C (34 pts): Dmitri Volkov has Tardy on 2024-11-04

Wrong-target gate: if more than 5 OTHER students had their attendance
changed on 2024-11-04, score = 0 (agent modified wrong records).
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any, List

sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_DATE = "2024-11-04"

EXPECTED_ATTENDANCE = [
    {"first_name": "Miguel", "last_name": "Santos", "status_variants": ("Present", "present", "P", "1")},
    {"first_name": "Aisha",  "last_name": "Patel",  "status_variants": ("Absent", "absent", "A", "0")},
    {"first_name": "Dmitri", "last_name": "Volkov",  "status_variants": ("Tardy", "tardy", "T", "Late", "late")},
]

CRITERIA_SCORES = [33, 33, 34]


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


def check_attendance_record(exec_in_env, first_name: str, last_name: str, status_variants: tuple) -> Dict[str, Any]:
    """Check a single student's attendance on the target date."""
    rows = _run_query(exec_in_env,
        f"SELECT a.attendance_id, a.attendance_date, a.status "
        f"FROM attendance a "
        f"INNER JOIN students s ON a.student_id = s.student_id "
        f"WHERE s.first_name = '{first_name}' AND s.last_name = '{last_name}' "
        f"AND a.attendance_date = '{TARGET_DATE}'")

    if not rows:
        return {"found": False, "correct": False,
                "feedback": f"{first_name} {last_name}: no attendance on {TARGET_DATE}"}

    actual_status = rows[0].get("status", "")
    correct = actual_status in status_variants
    return {
        "found": True,
        "correct": correct,
        "actual_status": actual_status,
        "expected_variants": status_variants,
        "feedback": f"{first_name} {last_name}: status='{actual_status}' (expected one of {status_variants}), correct={correct}",
    }


def wrong_target_gate(exec_in_env) -> bool:
    """Trigger if more than 5 unexpected students have attendance on target date."""
    rows = _run_query(exec_in_env,
        f"SELECT COUNT(*) as cnt FROM attendance a "
        f"INNER JOIN students s ON a.student_id = s.student_id "
        f"WHERE a.attendance_date = '{TARGET_DATE}' "
        f"AND NOT ("
        f"  (s.first_name='Miguel' AND s.last_name='Santos') OR "
        f"  (s.first_name='Aisha'  AND s.last_name='Patel')  OR "
        f"  (s.first_name='Dmitri' AND s.last_name='Volkov') "
        f")")
    if rows:
        try:
            return int(rows[0].get("cnt", 0)) > 5
        except (ValueError, TypeError):
            pass
    return False


VLM_PROMPT = """You are verifying if an agent successfully recorded attendance in OpenSIS.

The agent should have recorded attendance for three students on 2024-11-04:
- Miguel Santos: Present
- Aisha Patel: Absent
- Dmitri Volkov: Tardy

Look at the screenshot and respond in JSON:
{
    "is_sis_interface": true/false,
    "attendance_page_visible": true/false,
    "student_names_visible": true/false,
    "attendance_statuses_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_multi_student_attendance_audit(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify attendance records for Miguel Santos, Aisha Patel, Dmitri Volkov on 2024-11-04.
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
                "feedback": "Wrong-target gate triggered: too many unexpected students had attendance entered on 2024-11-04",
                "details": {"wrong_target": True},
            }

        total_score = 0
        for i, target in enumerate(EXPECTED_ATTENDANCE):
            check = check_attendance_record(
                exec_in_env,
                target["first_name"],
                target["last_name"],
                target["status_variants"],
            )
            result_details[f"{target['first_name']}_{target['last_name']}"] = check
            feedback_parts.append(check["feedback"])
            if check.get("correct"):
                total_score += CRITERIA_SCORES[i]

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
    criteria = [parsed.get("attendance_page_visible"), parsed.get("student_names_visible"), parsed.get("attendance_statuses_visible")]
    met = sum(1 for c in criteria if c)
    confidence_mult = {"high": 1.0, "medium": 0.9, "low": 0.8}.get(parsed.get("confidence", "low"), 0.8)
    score = int((met / 3) * 85 * confidence_mult)

    return {
        "passed": met >= 2,
        "score": score,
        "feedback": f"VLM fallback: {met}/3 criteria met | {parsed.get('reasoning', '')}",
        "details": {"vlm": parsed},
    }
